import Aqua
import TestCompatHygiene
using Test: @testset

@testset "aqua" begin
    Aqua.test_all(TestCompatHygiene)
end
