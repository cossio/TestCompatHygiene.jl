# TestCompatHygiene.jl

Aqua-style test helpers guarding **compat hygiene** in Julia packages that use

```toml
[workspace]
projects = ["test"]
```

## The invariant

`test/Project.toml` must **not** declare a `[compat]` entry for any name the
root `Project.toml` already owns:

- anything in the root's `[deps]`,
- anything in the root's `[compat]` (including `julia`),
- the package's own name.

Bounds for genuinely test-only dependencies (Aqua, SafeTestsets,
ExplicitImports, ...) are legitimate and are not flagged.

## Why this matters

When the root and test projects form one workspace, Pkg **intersects** compat
bounds across all workspace members into a single shared manifest. A bound
repeated in `test/Project.toml` therefore silently narrows the real resolve:
the root's declared bound stops being the effective one, and nothing warns you.
The root's `[compat]` says one thing, the manifest quietly obeys another.

Dependabot introduces exactly this failure mode. When an update job is rooted
at `/test`, it treats `test/Project.toml` as its own project file and
synthesizes a `[compat]` entry for every direct dep that lacks one (the
CompatHelper convention) — pinning deps the root already bounds, and shadowing
the root's declarations from then on.

## Usage

Add `TestCompatHygiene` to your test dependencies, then, mirroring Aqua.jl:

```julia
using MyPkg
import TestCompatHygiene

TestCompatHygiene.test_all(MyPkg)
```

On violation the test fails, and a warning names each offending entry along
with what the root declares:

```
test/Project.toml declares [compat] for 1 name(s) the root Project.toml already owns.
Workspace members share one manifest, so these bounds are intersected and silently narrow the root's.
Remove them from test/Project.toml:
    Preferences = "1.5.2"   (root declares "1.4.3")
```

## API

- `TestCompatHygiene.test_all(pkg; test_compat = true)` — run every check.
  Each check is `@testset`-based and can be disabled by its keyword; future
  checks will be added as new keywords, without breaking this call.
- `TestCompatHygiene.test_test_compat(pkg)` — the check above, individually.
- `TestCompatHygiene.check_test_compat(pkg)` — the non-throwing core: returns
  the sorted offender names (empty means clean) and warns, without `@test`.
  Useful in scripts or CI outside a test suite.

All entry points accept either a module (the package directory is derived via
`pkgdir`) or a plain path to a package root, so checks are unit-testable
against fixture directories.
