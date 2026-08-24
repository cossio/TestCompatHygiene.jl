# Changelog

## Unreleased

- Initial release: Aqua-style test helpers guarding compat hygiene in Julia packages that use a `[workspace]` test project, checking that `test/Project.toml` does not declare `[compat]` entries for names the root `Project.toml` already owns.
