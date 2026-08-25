"""
    TestCompatHygiene

Aqua-style test helpers guarding compat hygiene in packages that use
`[workspace] projects = ["test"]`.

The invariant: `test/Project.toml` must not declare a `[compat]` entry for any
name the root `Project.toml` already owns. The root and test projects are one
workspace, and Pkg *intersects* compat across workspace members into a single
shared manifest. A bound repeated in `test/` therefore silently narrows the
real resolve -- the root's declared bound stops being the effective one, with
no warning anywhere. Dependabot introduces exactly this when an update job is
rooted at `/test`: it treats `test/Project.toml` as its own project file and
synthesizes a compat entry for every direct dep that lacks one (the
CompatHelper convention).

Legitimately allowed: bounds for test-only deps (Aqua, SafeTestsets, ...),
i.e. anything the root project does not already name.

Usage, mirroring Aqua.jl:

```julia
using MyPkg
import TestCompatHygiene
TestCompatHygiene.test_all(MyPkg)
```

The public API is [`test_all`](@ref) -- the entry point, and all most users
need -- plus [`check_test_compat`](@ref), which returns the offenders as data
and needs no `Test` context, for use outside a test suite.
"""
module TestCompatHygiene

using Test: @testset, @test
import TOML

# Public API is deliberately small. `test_all` is the entry point (Aqua-style);
# `check_test_compat` is the only other name with a distinct capability -- it
# returns data and does not need a `Test` context, so it is usable from a plain
# CI script. Everything else is an implementation detail: `test_test_compat` is
# currently just `test_all` with one check, and `offending_compat_entries` /
# `root_owned_names` take paths and parsed TOML rather than a package. Marking a
# name public is a semver promise that is cheap to add later and breaking to
# take back, so they stay internal until something actually needs them.
public test_all, check_test_compat

# Resolve the package directory from a module (via `pkgdir`) or accept a plain
# path, so every check is unit-testable against fixture directories.
function project_dir(pkg::Module)
    dir = pkgdir(pkg)
    dir === nothing && throw(
        ArgumentError(
            "cannot determine the package directory of module $pkg; " *
                "pass the path to the package root instead"
        )
    )
    return dir
end
project_dir(path::AbstractString) = String(path)

"""
    root_owned_names(root::AbstractDict) -> Set{String}

Names whose version bounds belong to the root project: its dependencies,
anything it already pins in [compat] (including `julia`), and the package itself.
"""
function root_owned_names(root::AbstractDict)
    owned = Set{String}()
    union!(owned, keys(get(root, "deps", Dict{String, Any}())))
    union!(owned, keys(get(root, "compat", Dict{String, Any}())))
    haskey(root, "name") && push!(owned, String(root["name"]))
    return owned
end

"""
    offending_compat_entries(root_path, test_path) -> Vector{String}

Sorted names that `test_path` bounds but `root_path` already owns.
"""
function offending_compat_entries(root_path::AbstractString, test_path::AbstractString)
    isfile(test_path) || return String[]
    root = TOML.parsefile(root_path)
    tst = TOML.parsefile(test_path)
    test_compat = keys(get(tst, "compat", Dict{String, Any}()))
    return sort!(collect(intersect(test_compat, root_owned_names(root))))
end

"""
    check_test_compat(pkg::Union{Module,AbstractString}) -> Vector{String}

Compute the offending `test/Project.toml` [compat] entries for `pkg` and, if
any, `@warn` a diagnostic naming each offender alongside what the root
declares. Returns the sorted offender names (empty means clean). This is the
non-throwing core of the compat check, usable from a plain script or CI job
that has no `Test` context.
"""
function check_test_compat(pkg::Union{Module, AbstractString})
    dir = project_dir(pkg)
    root_path = joinpath(dir, "Project.toml")
    test_path = joinpath(dir, "test", "Project.toml")
    offenders = offending_compat_entries(root_path, test_path)

    if !isempty(offenders)
        root = TOML.parsefile(root_path)
        tst = TOML.parsefile(test_path)
        root_compat = get(root, "compat", Dict{String, Any}())
        io = IOBuffer()
        println(
            io, "test/Project.toml declares [compat] for ", length(offenders),
            " name(s) the root Project.toml already owns."
        )
        println(
            io, "Workspace members share one manifest, so these bounds are ",
            "intersected and silently narrow the root's."
        )
        println(io, "Remove them from test/Project.toml:")
        for k in offenders
            rb = get(root_compat, k, nothing)
            root_desc = rb === nothing ? "root lists it as a dep, unbounded" :
                string("root declares ", repr(rb))
            println(io, "    ", k, " = ", repr(tst["compat"][k]), "   (", root_desc, ")")
        end
        @warn String(take!(io))
    end

    return offenders
end

"""
    test_test_compat(pkg::Union{Module,AbstractString})

Test that `test/Project.toml` declares no [compat] entry for a name the root
`Project.toml` already owns (any root dep, anything in the root's [compat]
including `julia`, or the package's own name). On violation the test fails and
a warning names each offending entry and what the root declares.
"""
function test_test_compat(pkg::Union{Module, AbstractString})
    return @testset "test/Project.toml compat hygiene" begin
        # Comparing against String[] makes the failure output name the offenders.
        @test check_test_compat(pkg) == String[]
    end
end

"""
    test_all(pkg::Union{Module,AbstractString}; test_compat = true)

Run all TestCompatHygiene checks on `pkg` (a module, or a path to a package
root). Each check is `@testset`-based and can be disabled by its keyword;
future checks will be added as new keywords, without breaking this call.

Currently included checks:
- `test_compat`: `test_test_compat`, the `test/Project.toml` compat check
"""
function test_all(pkg::Union{Module, AbstractString}; test_compat::Bool = true)
    test_compat && test_test_compat(pkg)
    return nothing
end

end # module
