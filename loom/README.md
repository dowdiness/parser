# dowdiness/loom

Generic incremental parser framework for MoonBit, designed to pair with
[`dowdiness/seam`](../seam) (the language-agnostic CST) and
[`dowdiness/incr`](../incr) (reactive signals).

Provides: `Edit`/`Range` primitives (`core`), grammar composition
(`bridge`), reactive incremental pipeline (`pipeline`), damage-tracking
incremental parser (`incremental`), and a DOT visualisation trait (`viz`).

See [`dowdiness/parser`](../) for a complete reference implementation
using a lambda calculus grammar.
