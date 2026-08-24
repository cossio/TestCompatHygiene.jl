module compat_hygiene_tests
    include("compat_hygiene.jl")
end
module dogfood_tests
    include("dogfood.jl")
end
module aqua_tests
    include("aqua.jl")
end
module explicit_imports_tests
    include("explicit_imports.jl")
end
