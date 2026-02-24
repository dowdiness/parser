// Ast types for Lambda Calculus

///|
pub type VarName = String

///|
pub(all) enum Bop {
  Plus
  Minus
} derive(Show, Eq, FromJson, ToJson)

///|
pub(all) enum Ast {
  // Integer
  Int(Int)
  // Variable
  Var(VarName)
  // Lambda abstraction
  Lam(VarName, Ast)
  // Application
  App(Ast, Ast)
  // Binary operation
  Bop(Bop, Ast, Ast)
  // If-then-else
  If(Ast, Ast, Ast)
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
} derive(Show, FromJson, ToJson)

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
pub fn print_ast(ast : Ast) -> String {
  fn go(t : Ast) -> String {
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

  go(ast)
}

///|
/// Convert a AstNode to a Ast (discarding position information)
pub fn node_to_ast(node : AstNode) -> Ast {
  match node.kind {
    AstKind::Int(n) => Ast::Int(n)
    AstKind::Var(name) => Ast::Var(name)
    AstKind::Lam(param) => {
      let body = if node.children.length() > 0 {
        node_to_ast(node.children[0])
      } else {
        abort("Lambda node missing body child")
      }
      Ast::Lam(param, body)
    }
    AstKind::App => {
      let left = if node.children.length() > 0 {
        node_to_ast(node.children[0])
      } else {
        abort("App node missing left child")
      }
      let right = if node.children.length() > 1 {
        node_to_ast(node.children[1])
      } else {
        abort("App node missing right child")
      }
      Ast::App(left, right)
    }
    AstKind::Bop(op) => {
      let left = if node.children.length() > 0 {
        node_to_ast(node.children[0])
      } else {
        abort("Bop node missing left child")
      }
      let right = if node.children.length() > 1 {
        node_to_ast(node.children[1])
      } else {
        abort("Bop node missing right child")
      }
      Ast::Bop(op, left, right)
    }
    AstKind::If => {
      let cond = if node.children.length() > 0 {
        node_to_ast(node.children[0])
      } else {
        abort("If node missing condition child")
      }
      let then_expr = if node.children.length() > 1 {
        node_to_ast(node.children[1])
      } else {
        abort("If node missing then child")
      }
      let else_expr = if node.children.length() > 2 {
        node_to_ast(node.children[2])
      } else {
        abort("If node missing else child")
      }
      Ast::If(cond, then_expr, else_expr)
    }
    AstKind::Error(msg) => abort("Cannot convert error node to Ast: " + msg)
  }
}
