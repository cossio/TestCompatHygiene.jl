# Changelog

## 1.1.0

- The `test/Project.toml` compat check is now a no-op, logging an `@info` message, for packages whose root `[compat]` admits a Julia version older than 1.12 (including packages with no `julia` compat entry). Julia 1.11 and older ignore `[workspace]` and resolve `test/Project.toml` on its own, so repeated bounds are required there rather than redundant (see [JuliaTesting/Aqua.jl#392](https://github.com/JuliaTesting/Aqua.jl/pull/392)). The check applies unchanged once the root declares, for example, `julia = "1.12"`.
- `Pkg` is now a dependency, used to parse the root's `julia` compat entry.

## 1.0.0

- Initial release: Aqua-style test helpers guarding compat hygiene in Julia packages that use a `[workspace]` test project, checking that `test/Project.toml` does not declare `[compat]` entries for names the root `Project.toml` already owns.
