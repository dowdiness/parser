# Managing the Parser Project

This project is a **multi-module MoonBit codebase** composed of one application module and
three reusable library modules. Each library lives as a git submodule pointing to its own
GitHub repository and is published independently to mooncakes.io.

---

## Module Map

| Module | Path | GitHub | Purpose |
|--------|------|--------|---------|
| `dowdiness/parser` | `.` (root) | [dowdiness/parser](https://github.com/dowdiness/parser) | Lambda calculus example |
| `dowdiness/loom` | `loom/` | [dowdiness/loom](https://github.com/dowdiness/loom) | Generic parser framework |
| `dowdiness/seam` | `seam/` | [dowdiness/seam](https://github.com/dowdiness/seam) | Language-agnostic CST |
| `dowdiness/incr` | `incr/` | [dowdiness/incr](https://github.com/dowdiness/incr) | Reactive signals |

`loom` depends on `seam` and `incr`. `parser` depends on all three.

---

## Initial Setup

```bash
git clone --recursive https://github.com/dowdiness/parser.git
cd parser
moon check        # verify the whole module tree resolves
```

If you already cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

---

## Daily Development

### Running tests

```bash
moon test                    # 293 parser tests
cd loom && moon test         # 76 loom tests
cd seam && moon test         # seam tests
cd incr && moon test         # incr tests
```

Run all 369 tests in one pass:

```bash
moon test && cd loom && moon test && cd ../seam && moon test && cd ../incr && moon test && cd ..
```

### Check and format (run before every commit)

```bash
# In each module you changed:
moon info && moon fmt
moon check
```

`moon info` regenerates `.mbti` interface files. Always run it when public APIs change.

### Targeting a single package

```bash
moon test -p dowdiness/parser/src/examples/lambda/lexer
moon test -p dowdiness/loom/core
moon test -p dowdiness/loom/core -f edit_test.mbt
```

---

## Working Across Module Boundaries

Because `loom/`, `seam/`, and `incr/` are git submodules, changes to them require a
two-step commit: first push inside the submodule, then update the pointer in the parent repo.

### Making a change to loom

```bash
cd loom
# edit files
moon check && moon test
git add -p
git commit -m "feat: ..."
git push
cd ..
git add loom                  # stage the updated pointer
git commit -m "chore: update loom submodule"
```

### Pulling the latest version of all submodules

```bash
git submodule update --remote   # fetch HEAD of each submodule's main branch
git add loom seam incr
git commit -m "chore: update submodule pointers"
```

### Syncing after someone else updated a pointer

```bash
git pull
git submodule update --init     # materialise any new pointer commits
```

---

## Publishing to mooncakes.io

Each module is published independently with `moon publish`, run from that module's root.

### Prerequisites

```bash
moon register   # first time only — creates a mooncakes.io account
moon login      # subsequent sessions
```

### Dependency requirement

`moon publish` requires all deps to be **version deps**, not path deps. Before publishing
`loom`, its `moon.mod.json` must look like:

```json
"deps": {
  "dowdiness/seam": "0.1.0",
  "dowdiness/incr": "0.3.2"
}
```

not the local path form used during development:

```json
"deps": {
  "dowdiness/seam": { "path": "../seam" },
  "dowdiness/incr": { "path": "../incr" }
}
```

### Publish workflow

```bash
# 1. Publish leaf dependencies first (if versions changed)
cd seam && moon publish && cd ..
cd incr && moon publish && cd ..

# 2. Switch loom deps from path → version in loom/moon.mod.json
#    (edit manually — bump versions to match what was just published)

# 3. Publish loom
cd loom && moon publish && cd ..

# 4. Revert loom/moon.mod.json back to path deps for local development
#    (git checkout loom/moon.mod.json  — or keep version deps if stable)
```

### Required moon.mod.json fields

Every publishable module needs these fields or mooncakes.io will reject it:

```json
{
  "name": "dowdiness/<module>",
  "version": "X.Y.Z",
  "readme": "README.md",
  "repository": "https://github.com/dowdiness/<module>",
  "license": "Apache-2.0",
  "keywords": ["..."],
  "description": "..."
}
```

`loom` is currently missing `readme`, `repository`, `license`, and `keywords` — add these
before its first publish.

### Version bumping

Follow [Semantic Versioning](https://semver.org/):

| Change | Bump |
|--------|------|
| Incompatible API change | MAJOR |
| New backward-compatible feature | MINOR |
| Bug fix | PATCH |

---

## Adding a New Module as a Submodule

Follow the pattern used for `loom` (2026-03-01):

```bash
# 1. Create the module directory and its moon.mod.json
mkdir newmod && cd newmod
# ... add source files ...

# 2. Init, commit, push to GitHub
git init -b main
git add .
git commit -m "initial: <description>"
gh repo create dowdiness/newmod --public --source=. --remote=origin --push

# 3. Remove from parent's tracked files and re-add as submodule
cd ..
git rm -r --cached newmod/
git commit -m "chore: untrack newmod/ files (converting to git submodule)"
rm -rf newmod/
git submodule add https://github.com/dowdiness/newmod.git newmod
git commit -m "chore: add dowdiness/newmod as git submodule"

# 4. Register in parser's moon.mod.json
#    Add: "dowdiness/newmod": { "path": "newmod" }
```

---

## Future: Switching to mooncakes.io Registry

Once `seam`, `incr`, and `loom` are stable and published, you can replace path deps with
version deps permanently:

```json
"deps": {
  "dowdiness/seam": "0.1.0",
  "dowdiness/incr": "0.3.2",
  "dowdiness/loom": "0.1.0"
}
```

Then the git submodules are optional — consumers can install via `moon add` without cloning
the submodule repos. The submodules stay useful for development, but are no longer required.
