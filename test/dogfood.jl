import TestCompatHygiene
using Test: @testset

# The package must obey its own invariant.
@testset verbose = true "dogfood" begin
    TestCompatHygiene.test_all(TestCompatHygiene)
end
