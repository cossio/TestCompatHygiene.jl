import TestCompatHygiene
using TestCompatHygiene: check_test_compat, offending_compat_entries, root_owned_names
using Test

const FIXTURES = joinpath(@__DIR__, "fixtures")
fixture(name) = joinpath(FIXTURES, name)

# Trimmed-down copies of real Project.toml pairs from github.com/cossio repos
# (state as of 2026-08-24), which is where each expectation below comes from.
const EXPECTED = Dict(
    # root declares Preferences = "1.4.3", test pins "1.5.2"
    "Pfam" => ["Preferences"],
    "GenerativeMetrics" => ["Statistics"],
    "IsingModels" => ["Statistics"],
    # Statistics is a root dep without a root [compat] bound -- still owned
    "TeacherStudentLowRankRBM" => ["Statistics"],
    "SharedRBMs" => ["RestrictedBoltzmannMachines", "Statistics"],
    # these four pin the package's own name
    "Infernal" => ["Infernal"],
    "LatticeProteins" => ["LatticeProteins"],
    "Logomaker" => ["Logomaker"],
    "ProxRBMs" => ["ProxRBMs"],
    # clean: every test [compat] entry is a genuinely test-only dep
    "Rfam" => String[],
    "HMMER" => String[],
    # no test/Project.toml at all is trivially clean
    "no_test_project" => String[],
)

@testset verbose = true "offending_compat_entries on fixtures" begin
    for (name, expected) in sort!(collect(EXPECTED); by = first)
        @testset "$name" begin
            dir = fixture(name)
            root_path = joinpath(dir, "Project.toml")
            test_path = joinpath(dir, "test", "Project.toml")
            @test offending_compat_entries(root_path, test_path) == expected
        end
    end
end

@testset "check_test_compat warns on violations, is silent when clean" begin
    for (name, expected) in EXPECTED
        if isempty(expected)
            # zero log patterns asserts that nothing is logged
            @test (@test_logs check_test_compat(fixture(name))) == expected
        else
            @test (@test_logs (:warn, r"already owns") check_test_compat(fixture(name))) == expected
        end
    end
end

@testset "warning names the offender and the root's declaration" begin
    logs, offenders = Test.collect_test_logs() do
        check_test_compat(fixture("Pfam"))
    end
    @test offenders == ["Preferences"]
    msg = string(only(logs).message)
    @test occursin("Remove them from test/Project.toml", msg)
    @test occursin("Preferences = \"1.5.2\"", msg)
    @test occursin("root declares \"1.4.3\"", msg)

    # A root dep without a root [compat] bound is reported as such.
    logs, offenders = Test.collect_test_logs() do
        check_test_compat(fixture("TeacherStudentLowRankRBM"))
    end
    @test offenders == ["Statistics"]
    @test occursin("root lists it as a dep, unbounded", string(only(logs).message))
end

@testset "root_owned_names" begin
    root = Dict{String, Any}(
        "name" => "Foo",
        "deps" => Dict{String, Any}("A" => "uuid-a"),
        "compat" => Dict{String, Any}("B" => "1", "julia" => "1.12"),
    )
    @test root_owned_names(root) == Set(["Foo", "A", "B", "julia"])
    @test root_owned_names(Dict{String, Any}()) == Set{String}()
end

@testset "module and path inputs" begin
    @test TestCompatHygiene.project_dir(TestCompatHygiene) == pkgdir(TestCompatHygiene)
    @test check_test_compat(TestCompatHygiene) == String[]
    # modules that do not belong to a package are rejected
    @test_throws ArgumentError TestCompatHygiene.project_dir(Main)
end

# A testset type that records results without printing or throwing, so we can
# assert that test_test_compat *fails* on a violation without failing (or
# polluting the output of) this suite. Note that a nested @testset with no
# explicit type inherits the parent's type, so the testset opened inside
# test_test_compat becomes a QuietTestSet too -- which is exactly what makes
# this quiet: its Fail results land in our `results` instead of printing.
mutable struct QuietTestSet <: Test.AbstractTestSet
    description::String
    results::Vector{Any}
end
QuietTestSet(desc::AbstractString; kwargs...) = QuietTestSet(String(desc), [])
Test.record(ts::QuietTestSet, res) = (push!(ts.results, res); res)
function Test.finish(ts::QuietTestSet)
    # attach to the parent testset, mirroring DefaultTestSet's convention
    Test.get_testset_depth() != 0 && Test.record(Test.get_testset(), ts)
    return ts
end

function quiet_run(f)
    # swallow and assert the expected warning; run f under a QuietTestSet
    return @test_logs (:warn, r"already owns") match_mode = :any begin
        @testset QuietTestSet "quiet" begin
            f()
        end
    end
end

@testset "the @test inside test_test_compat fails on violations" begin
    for name in ("Pfam", "SharedRBMs", "Infernal")
        ts = quiet_run(() -> TestCompatHygiene.test_test_compat(fixture(name)))
        inner = only(ts.results)
        @test inner isa QuietTestSet
        @test any(r -> r isa Test.Fail, inner.results)
    end
    # test_all reaches the same check
    ts = quiet_run(() -> TestCompatHygiene.test_all(fixture("Pfam")))
    @test any(r -> r isa Test.Fail, only(ts.results).results)
end

@testset "test_test_compat passes on clean packages" begin
    TestCompatHygiene.test_test_compat(fixture("Rfam"))
    TestCompatHygiene.test_test_compat(fixture("HMMER"))
    TestCompatHygiene.test_all(fixture("no_test_project"))
end

@testset "test_all keywords can disable checks" begin
    # must not touch the (violating) fixture at all
    @test_logs TestCompatHygiene.test_all(fixture("Pfam"); test_compat = false)
end
