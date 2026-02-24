# seam

Language-agnostic concrete syntax tree (CST) infrastructure for incremental parsers in MoonBit.

Modelled after [rowan](https://github.com/rust-analyzer/rowan).

## Key types

- `CstNode` — immutable interior node (position-independent, content-addressed)
- `CstToken` — immutable leaf token
- `SyntaxNode` — ephemeral positioned view over a `CstNode`
- `EventBuffer` — accumulates `ParseEvent`s; use `buf.build_tree(root_kind)` to construct the tree
- `RawKind` — language-agnostic node/token kind (newtype over `Int`)

## Usage

See the [API contract](https://github.com/dowdiness/parser/blob/main/docs/api-contract.md) for stability guarantees.
