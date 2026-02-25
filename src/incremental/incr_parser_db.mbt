///|
/// Tokenization stage output — designed for Memo[T : Eq] boundaries.
/// Eq on Array[TokenInfo] is element-wise; enables backdating when
/// the same source re-tokenizes to an identical token stream.
pub(all) enum TokenStage {
  Ok(Array[@token.TokenInfo])
  Err(String)
} derive(Eq, Show)

///|
/// Salsa-style incremental pipeline for the lambda calculus parser.
///
/// source_text : Signal[String]
///   → tokens : Memo[TokenStage]
///   → cst    : Memo[CstStage]
///   → term   : Memo[AstNode]
///
/// Calling set_source() invalidates the full pipeline.
/// Each Memo stage backdates if its output equals the previous value —
/// CstStage via cached hash (O(1)), AstNode via structure-only Eq.
///
/// **Lifetime:** one ParserDb per document editing session.
pub struct ParserDb {
  priv source_text : @incr.Signal[String]
  priv cst_memo : @incr.Memo[@pipeline.CstStage]
  priv term_memo : @incr.Memo[@ast.AstNode]
}

///|
pub fn ParserDb::new(initial_source : String) -> ParserDb {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, initial_source, label="source_text")

  let tokens_memo = @incr.Memo::new(
    rt,
    () => {
      TokenStage::Ok(@lexer.tokenize(source_text.get())) catch {
        @lexer.TokenizationError(msg) => TokenStage::Err(msg)
      }
    },
    label="tokens",
  )

  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> @pipeline.CstStage {
      match tokens_memo.get() {
        TokenStage::Err(msg) => {
          // Tokenization failed: return an empty SourceFile CST as placeholder.
          // term() will detect this via tokens_memo and return AstNode::error.
          let (empty_cst, _, _) = @parse.parse_cst_recover_with_tokens(
            "",
            [],
            None,
          )
          @pipeline.CstStage::{
            cst: empty_cst,
            diagnostics: ["tokenization: " + msg],
            is_lex_error: true,
          }
        }
        TokenStage::Ok(tokens) => {
          let source = source_text.get()
          let (cst, diags, _reuse_count) = @parse.parse_cst_recover_with_tokens(
            source,
            tokens,
            None,
          )
          @pipeline.CstStage::{
            cst,
            diagnostics: diags.map(fn(d) {
              d.message +
              " [" +
              d.start.to_string() +
              "," +
              d.end.to_string() +
              "]"
            }),
            is_lex_error: false,
          }
        }
      }
    },
    label="cst",
  )

  let term_memo = @incr.Memo::new(
    rt,
    () => {
      match tokens_memo.get() {
        TokenStage::Err(msg) =>
          return @ast.AstNode::error("Tokenization error: " + msg, 0, 0)
        TokenStage::Ok(_) => {
          let syntax = @seam.SyntaxNode::from_cst(cst_memo.get().cst)
          @parse.syntax_node_to_ast_node(syntax, Ref::new(0))
        }
      }
    },
    label="term",
  )
  { source_text, cst_memo, term_memo }
}

///|
/// Update the source text, invalidating tokens and cst memos.
/// If the new source equals the current source (String::Eq), Signal::set
/// is a no-op and no recomputation occurs.
pub fn ParserDb::set_source(self : ParserDb, source : String) -> Unit {
  self.source_text.set(source)
}

///|
/// Return the current CstStage (parse result + normalized diagnostics).
/// Triggers memo evaluation if the source has changed since last call.
pub fn ParserDb::cst(self : ParserDb) -> @pipeline.CstStage {
  self.cst_memo.get()
}

///|
/// Return normalized parse diagnostic strings.
/// On tokenization error this contains the tokenization message.
/// On parse error this contains position-annotated error strings.
pub fn ParserDb::diagnostics(self : ParserDb) -> Array[String] {
  self.cst_memo.get().diagnostics.copy()
}

///|
/// Return an AstNode for the current source.
/// Backed by term_memo: on a warm call (no source change) the Runtime skips
/// recomputation and returns the cached AstNode immediately.
///
/// Error routing: on tokenization failure, returns AstNode::error(...)
/// so callers do not need to check diagnostics() separately.
pub fn ParserDb::term(self : ParserDb) -> @ast.AstNode {
  self.term_memo.get()
}
