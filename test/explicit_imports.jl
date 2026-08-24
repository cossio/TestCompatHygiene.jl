import ExplicitImports
import TestCompatHygiene
using Test: @testset

@testset "ExplicitImports" begin
    ExplicitImports.test_explicit_imports(TestCompatHygiene)
end
