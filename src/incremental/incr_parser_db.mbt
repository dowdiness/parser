///|
/// Tokenization stage output — designed for Memo[T : Eq] boundaries.
/// Eq on Array[TokenInfo] is element-wise; enables backdating when
/// the same source re-tokenizes to an identical token stream.
pub(all) enum TokenStage {
  Ok(Array[@token.TokenInfo])
  Err(String)
} derive(Eq, Show)

///|
/// Green parse stage output — designed for Memo[T : Eq] boundaries.
/// CstNode::Eq uses a cached structural hash (O(1) rejection path),
/// so comparing two CstStage values is very cheap.
/// diagnostics is Array[String] rather than Array[Diagnostic] because
/// Diagnostic[T] does not derive Eq; normalized strings keep the Eq boundary clean.
pub(all) struct CstStage {
  cst : @seam.CstNode
  diagnostics : Array[String]
} derive(Eq, Show)

///|
/// Salsa-style incremental pipeline for the lambda calculus parser.
///
/// source_text : Signal[String]
///   → tokens : Memo[TokenStage]
///   → cst    : Memo[CstStage]
///
/// Calling set_source() invalidates tokens_memo and cst_memo.
/// If re-parse produces a CstNode equal to the previous one (CstNode::Eq),
/// downstream stages are backdated — they skip recomputation.
///
/// **Lifetime:** one ParserDb per document editing session.
pub struct ParserDb {
  priv source_text : @incr.Signal[String]
  priv tokens_memo : @incr.Memo[TokenStage]
  priv cst_memo : @incr.Memo[CstStage]
}

///|
pub fn ParserDb::new(initial_source : String) -> ParserDb {
  let rt = @incr.Runtime::new()
  let source_text = @incr.Signal::new(rt, initial_source, label="source_text")

  let tokens_memo = @incr.Memo::new(
    rt,
    fn() -> TokenStage {
      TokenStage::Ok(@lexer.tokenize(source_text.get())) catch {
        @lexer.TokenizationError(msg) => TokenStage::Err(msg)
      }
    },
    label="tokens",
  )

  let cst_memo = @incr.Memo::new(
    rt,
    fn() -> CstStage {
      match tokens_memo.get() {
        TokenStage::Err(msg) => {
          // Tokenization failed: return an empty SourceFile CST as placeholder.
          // term() will detect this via tokens_memo and return AstNode::error.
          let (empty_cst, _, _) = @parse.parse_cst_recover_with_tokens(
            "",
            [],
            None,
          )
          CstStage::{ cst: empty_cst, diagnostics: ["tokenization: " + msg] }
        }
        TokenStage::Ok(tokens) => {
          let source = source_text.get()
          let (cst, diags, _reuse_count) = @parse.parse_cst_recover_with_tokens(
            source,
            tokens,
            None,
          )
          CstStage::{
            cst,
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
    },
    label="cst",
  )
  { source_text, tokens_memo, cst_memo }
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
pub fn ParserDb::cst(self : ParserDb) -> CstStage {
  self.cst_memo.get()
}

///|
/// Return normalized parse diagnostic strings.
/// On tokenization error this contains the tokenization message.
/// On parse error this contains position-annotated error strings.
pub fn ParserDb::diagnostics(self : ParserDb) -> Array[String] {
  self.cst_memo.get().diagnostics
}

///|
/// Return an AstNode for the current source.
///
/// Option B error routing: on tokenization failure, returns AstNode::error(...)
/// matching IncrementalParser::parse behavior. Callers do not need to check
/// diagnostics() to detect unrecoverable failures — the tree itself carries
/// the error signal via AstKind::Error.
pub fn ParserDb::term(self : ParserDb) -> @ast.AstNode {
  match self.tokens_memo.get() {
    TokenStage::Err(msg) =>
      @ast.AstNode::error("Tokenization error: " + msg, 0, 0)
    TokenStage::Ok(_) => {
      let syntax = @seam.SyntaxNode::from_cst(self.cst_memo.get().cst)
      @parse.syntax_node_to_ast_node(syntax, Ref::new(0))
    }
  }
}
