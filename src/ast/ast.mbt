// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson)

///|
pub(all) enum Term {
  // Integer
  Int(Int)
  // Variable
  Var(VarName)
  // Lambda abstraction
  Lam(VarName, Term)
  // Application
  App(Term, Term)
  // Binary operation
  Bop(Bop, Term, Term)
  // If-then-else
  If(Term, Term, Term)
} derive(Show, Eq)

///|
/// Ast kind for positioned nodes
pub(all) enum AstKind {
  Int(Int) // Integer literal
  Var(String) // Variable
  Lam(String) // Lambda abstraction (parameter name, body is children[0])
  App // Application (left is children[0], right is children[1])
  Bop(Bop) // Binary operation (operands in children[0] and children[1])
  If // If-then-else (condition, then, else in children)
  Error(String) // Error node for recovery
} derive(Show, Eq, FromJson, ToJson)

///|
/// AST node with source position and unique identity
pub(all) struct AstNode {
  kind : AstKind // Kind of term
  start : Int // Start byte offset in source
  end : Int // End byte offset in source
  node_id : Int // Unique node identifier
  children : Array[AstNode] // Child nodes
} derive(Show, FromJson, ToJson)

///|
/// Structure-only equality for AstNode: compares kind and children, ignoring
/// start/end byte offsets and node_id. Two nodes are equal iff they have the
/// same syntactic structure regardless of where they appear in the source.
///
/// This is the right semantic for Memo[AstNode] backdating: an edit that shifts
/// all offsets (e.g. inserting a leading space) but preserves AST shape will
/// still be considered equal, skipping downstream recomputation.
pub impl Eq for AstNode with equal(self, other : AstNode) -> Bool {
  if self.kind != other.kind ||
    self.children.length() != other.children.length() {
    return false
  }
  for i, child in self.children {
    if child != other.children[i] {
      return false
    }
  }
  true
}

///|
/// Create a new AstNode
pub fn AstNode::new(
  kind : AstKind,
  start : Int,
  end : Int,
  node_id : Int,
  children : Array[AstNode],
) -> AstNode {
  { kind, start, end, node_id, children }
}

///|
/// Create an error node
pub fn AstNode::error(
  message : String,
  position : Int,
  node_id : Int,
) -> AstNode {
  AstNode::new(AstKind::Error(message), position, position, node_id, [])
}

///|
/// Print a AstNode
pub fn print_ast_node(node : AstNode) -> String {
  fn go(n : AstNode) -> String {
    match n.kind {
      AstKind::Int(i) => i.to_string()
      AstKind::Var(x) => x
      AstKind::Lam(param) => {
        let body = if n.children.length() > 0 { go(n.children[0]) } else { "?" }
        "(λ" + param + ". " + body + ")"
      }
      AstKind::App => {
        let left = if n.children.length() > 0 { go(n.children[0]) } else { "?" }
        let right = if n.children.length() > 1 {
          go(n.children[1])
        } else {
          "?"
        }
        "(" + left + " " + right + ")"
      }
      AstKind::Bop(Plus) => {
        let left = if n.children.length() > 0 { go(n.children[0]) } else { "?" }
        let right = if n.children.length() > 1 {
          go(n.children[1])
        } else {
          "?"
        }
        "(" + left + " + " + right + ")"
      }
      AstKind::Bop(Minus) => {
        let left = if n.children.length() > 0 { go(n.children[0]) } else { "?" }
        let right = if n.children.length() > 1 {
          go(n.children[1])
        } else {
          "?"
        }
        "(" + left + " - " + right + ")"
      }
      AstKind::If => {
        let cond = if n.children.length() > 0 { go(n.children[0]) } else { "?" }
        let then_expr = if n.children.length() > 1 {
          go(n.children[1])
        } else {
          "?"
        }
        let else_expr = if n.children.length() > 2 {
          go(n.children[2])
        } else {
          "?"
        }
        "if " + cond + " then " + then_expr + " else " + else_expr
      }
      AstKind::Error(msg) => "<error: " + msg + ">"
    }
  }

  go(node)
}

///|
pub fn print_term(term : Term) -> String {
  fn go(t : Term) -> String {
    match t {
      Int(i) => i.to_string()
      Var(x) => x
      Lam(x, t) => "(λ" + x + ". " + go(t) + ")"
      App(t1, t2) => "(" + go(t1) + " " + go(t2) + ")"
      Bop(Plus, t1, t2) => "(" + go(t1) + " + " + go(t2) + ")"
      Bop(Minus, t1, t2) => "(" + go(t1) + " - " + go(t2) + ")"
      If(t1, t2, t3) => "if " + go(t1) + " then " + go(t2) + " else " + go(t3)
    }
  }

  go(term)
}

///|
/// Convert a AstNode to a Term (discarding position information)
pub fn node_to_term(node : AstNode) -> Term {
  match node.kind {
    AstKind::Int(n) => Term::Int(n)
    AstKind::Var(name) => Term::Var(name)
    AstKind::Lam(param) => {
      let body = if node.children.length() > 0 {
        node_to_term(node.children[0])
      } else {
        abort("Lambda node missing body child")
      }
      Term::Lam(param, body)
    }
    AstKind::App => {
      let left = if node.children.length() > 0 {
        node_to_term(node.children[0])
      } else {
        abort("App node missing left child")
      }
      let right = if node.children.length() > 1 {
        node_to_term(node.children[1])
      } else {
        abort("App node missing right child")
      }
      Term::App(left, right)
    }
    AstKind::Bop(op) => {
      let left = if node.children.length() > 0 {
        node_to_term(node.children[0])
      } else {
        abort("Bop node missing left child")
      }
      let right = if node.children.length() > 1 {
        node_to_term(node.children[1])
      } else {
        abort("Bop node missing right child")
      }
      Term::Bop(op, left, right)
    }
    AstKind::If => {
      let cond = if node.children.length() > 0 {
        node_to_term(node.children[0])
      } else {
        abort("If node missing condition child")
      }
      let then_expr = if node.children.length() > 1 {
        node_to_term(node.children[1])
      } else {
        abort("If node missing then child")
      }
      let else_expr = if node.children.length() > 2 {
        node_to_term(node.children[2])
      } else {
        abort("If node missing else child")
      }
      Term::If(cond, then_expr, else_expr)
    }
    AstKind::Error(msg) => abort("Cannot convert error node to Term: " + msg)
  }
}
