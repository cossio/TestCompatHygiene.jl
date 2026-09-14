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

The check only applies to packages whose root `[compat]` requires Julia 1.12 or
later, for example `julia = "1.12"`. For a package whose `julia` compat still
admits an older version (say `julia = "1.10"`, or no `julia` entry at all) the
check is a no-op: it passes trivially and logs an `@info` message explaining
why. See [When the check applies](#when-the-check-applies) below.

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

## When the check applies

`[workspace]` is a Julia 1.12 feature. Julia 1.11 and older ignore it and
resolve `test/Project.toml` into its own manifest, without inheriting the
root's compat bounds. For a package that still supports those versions, a
bound repeated in `test/Project.toml` is *required*, not redundant: removing it
would leave the test environment unbounded there. This is the concern raised in
[JuliaTesting/Aqua.jl#392](https://github.com/JuliaTesting/Aqua.jl/pull/392),
and the check follows the resolution adopted there.

The gate is decided from the package's declared `julia` compat, not from the
Julia version running the tests: the check applies only when the root
`[compat]` admits no version older than 1.12, so that there is no way the
package manager resolves the test project without the workspace. Until then the
check is a no-op, logging:

```
┌ Info: TestCompatHygiene's test/Project.toml compat check is a no-op: the root Project.toml declares `julia = "1.10"` and so admits Julia versions older than 1.12. [...] The check will apply once the `julia` compat requires 1.12 or later.
└ @ TestCompatHygiene
```

## Installation

The package is registered in the [General registry](https://github.com/JuliaRegistries/General).
Since it is a test helper, add it to your test environment:

```julia
julia --project=test -e 'using Pkg; Pkg.add("TestCompatHygiene")'
```

or, from the Pkg REPL (press `]`) with the test project active:

```
pkg> add TestCompatHygiene
```

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
┌ Warning: test/Project.toml declares [compat] for 1 name(s) the root Project.toml already owns.
│ Workspace members share one manifest, so these bounds are intersected and silently narrow the root's.
│ Remove them from test/Project.toml:
│     Preferences = "1.5.2"   (root declares "1.4.3")
└ @ TestCompatHygiene
test/Project.toml compat hygiene: Test Failed at .../src/TestCompatHygiene.jl:135
  Expression: check_test_compat(pkg) == String[]
   Evaluated: ["Preferences"] == String[]
```

The offenders are named twice: in the warning, with the bound `test/` declares
and the one the root declares, and in the failed `@test` itself, because the
check compares the offender vector against `String[]` rather than asserting a
bare `isempty`.

## API

The public API is one name:

- `TestCompatHygiene.test_all(pkg; test_compat = true)` — run every check.
  Each check is `@testset`-based and can be disabled by its keyword; future
  checks will be added as new keywords, without breaking this call.

It accepts either a module (the package directory is derived via `pkgdir`) or a
plain path to a package root, so checks are unit-testable against fixture
directories.

Everything else — `test_test_compat`, `check_test_compat`, `requires_julia_1_12`,
`offending_compat_entries`, `root_owned_names` — is internal: callable and
documented, but not covered by semver. `check_test_compat(pkg)` is the useful
one of those if you want the offenders as data outside a test suite: it returns
the sorted offender names (empty means clean) and warns, without `@test`.

Marking a name public is cheap to add in a minor release and breaking to take
back, so nothing is promoted until there is a concrete reason.
