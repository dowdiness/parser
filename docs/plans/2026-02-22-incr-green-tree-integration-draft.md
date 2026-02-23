# Draft: Integrate `green-tree` with `incr` (Salsa-style)

**Date:** 2026-02-22  
**Status:** Draft (architecture + API sketch)

## Goal

Use `/home/antisatori/ghq/github.com/dowdiness/incr` as the incremental
computation engine for parser stages, with `GreenNode` as a memoized value.

This mirrors the Salsa idea:
- inputs as `Signal`
- derived stages as `Memo`
- downstream invalidation controlled by value equality (backdating)

## Feasibility Summary

This is feasible with the current codebase:
- `incr` already provides `Signal`, `Memo`, auto dependency tracking, and backdating.
- `Memo::new` requires `T : Eq`.
- `green-tree` `GreenNode` already implements `Eq` with a hash fast path.

Result: `Memo[GreenNode]` is a valid and efficient stage boundary.

## Non-Goals In This Draft

- No migration plan from existing `IncrementalParser`.
- No API stability promises.
- No publish/release decisions.

## Pre-Implementation Decisions (Must Resolve First)

1. `ParserDb::term()` behavior on tokenization failure.
   - Option A: keep current draft behavior (fallback empty `SourceFile` green tree
     + diagnostics; `term()` still returns a term tree).
   - Option B: return an explicit error-term shape matching
     `IncrementalParser::parse` tokenization-error behavior.
2. Phase 2 ownership model for previous green-tree state.
   - Pick exactly one model from "Phase 2: Add subtree-reuse path" to avoid
     mixed sources of truth.

## Deferred Until Implementation (Non-Blocking To Start)

- Final migration strategy from existing `IncrementalParser`.
- Whether to add a memoized term-level stage later (if a stable Eq-friendly
  term-stage representation is introduced).

---

## Proposed Dataflow

Minimal pipeline:

1. `source_text : Signal[String]`
2. `tokens : Memo[TokenStage]`
3. `green : Memo[GreenStage]`
4. `term : @term.TermNode` (computed on demand from current green stage)

Memo stages use Eq-friendly result types to satisfy `Memo[T : Eq]`.

## Proposed Draft Types

```moonbit
///| Tokenization stage output designed for Memo[T : Eq]
pub(all) enum TokenStage {
  Ok(Array[@token.TokenInfo])
  Err(String)
} derive(Eq, Show)

///| Green parse stage output designed for Memo[T : Eq]
pub(all) struct GreenStage {
  green : @green_tree.GreenNode
  diagnostics : Array[String] // normalized diagnostics for Eq friendliness
} derive(Eq, Show)
```

Notes:
- `ParseDiagnostic` in parser currently derives `Show` but not `Eq`.
- Using normalized `Array[String]` avoids adding Eq requirements to parser
  diagnostics during the first integration pass.
- `reuse_count` is a parser-internal reuse statistic, not semantic parse output.
  Keep it out of memoized Eq boundaries to avoid spurious invalidation.

---

## Proposed `ParserDb` Skeleton

```moonbit
///|
pub struct ParserDb {
  rt : @incr.Runtime
  source_text : @incr.Signal[String]
  tokens_memo : @incr.Memo[TokenStage]
  green_memo : @incr.Memo[GreenStage]
}

///|
pub impl @incr.IncrDb for ParserDb with runtime(self) {
  self.rt
}
```

## Construction Sketch

```moonbit
///|
pub fn ParserDb::new(initial_source : String) -> ParserDb {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, initial_source, label="source_text")

  let tokens_memo = @incr.Memo::new(rt, fn() {
    match @lexer.tokenize(source_text.get()) {
      tokens => TokenStage::Ok(tokens)
    } catch {
      @lexer.TokenizationError(msg) => TokenStage::Err(msg)
    }
  }, label="tokens")

  let green_memo = @incr.Memo::new(rt, fn() {
    match tokens_memo.get() {
      TokenStage::Err(msg) =>
        GreenStage::{
          green: @green_tree.GreenNode::new(@syntax.SourceFile.to_raw(), []),
          diagnostics: ["tokenization: " + msg],
        }
      TokenStage::Ok(tokens) => {
        let (green, diags, _reuse_count) = @parse.parse_green_recover_with_tokens(
          source_text.get(),
          tokens,
          None, // phase 1: no reuse cursor inside incr memo
        )
        GreenStage::{
          green,
          diagnostics: diags.map(fn(d) {
            d.message +
            " [" +
            d.start.to_string() +
            "," +
            d.end.to_string() +
            "]"
          }),
        }
      }
    }
  }, label="green")
  { rt, source_text, tokens_memo, green_memo }
}
```

---

## Public API Sketch

```moonbit
///|
pub fn ParserDb::set_source(self : ParserDb, source : String) -> Unit {
  self.source_text.set(source)
}

///|
pub fn ParserDb::green(self : ParserDb) -> GreenStage {
  self.green_memo.get()
}

///|
pub fn ParserDb::diagnostics(self : ParserDb) -> Array[String] {
  self.green_memo.get().diagnostics
}

///|
pub fn ParserDb::term(self : ParserDb) -> @term.TermNode {
  @parse.green_to_term_node(self.green_memo.get().green, 0, Ref::new(0))
}
```

---

## Integration Phases

### Phase 1: Coarse integration (recommended first)

- Build the `ParserDb` pipeline with `cursor=None`.
- Rely on `incr` backdating and `GreenNode Eq` to avoid downstream recompute.
- Keep `term()` always available by deriving `TermNode` from current green stage.
- Keep existing `IncrementalParser` unchanged.

Expected benefit:
- Clear Salsa-like architecture
- Stable memo boundaries
- Lower recomputation in downstream stages when parse result is unchanged

### Phase 2: Add subtree-reuse path

Goal: combine `incr` memoization with existing cursor-based subtree reuse.

Options:
1. Keep cursor reuse outside memo and store previous green tree in a tracked
   input cell that feeds the parse stage.
2. Add an explicit update method that computes `GreenStage` via
   `parse_green_recover_with_tokens(..., Some(cursor))`, then writes result to a
   `Signal[GreenStage]` used by downstream memos.

Decision point:
- choose one ownership model for previous-tree state to avoid mixed sources of truth.

---

## Risks And Constraints

- `Memo` closures cannot directly expose raised errors; stage outputs should use
  Eq-friendly result enums or normalized diagnostics.
- If diagnostics are represented with non-Eq structures, backdating cannot be
  applied at that stage.
- `source_text.get()` read in multiple memos is fine; dependency tracking
  deduplicates and remains correct.

---

## Minimal Validation Checklist

1. Create `ParserDb` with source `"x + 1"` and read `green()`.
2. Set source to an equivalent text producing same green tree and verify
   downstream memo recomputation is skipped (backdating behavior).
3. Set source to invalid text and verify `diagnostics()` returns normalized errors.
4. Exercise tokenization-failure path and verify `term()` behavior matches the
   decision from "Pre-Implementation Decisions".
5. Add one integration test comparing `ParserDb::term()` against current
   `parse_tree` output for a set of fixtures.

---

## Suggested Implementation Location

If implemented in this repository, start under:
- `src/incremental/incr_parser_db.mbt`
- `src/incremental/incr_parser_db_test.mbt`

Keep this draft as the source of truth until first implementation lands.
