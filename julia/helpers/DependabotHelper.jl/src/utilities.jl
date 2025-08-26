# Core utility functions for DependabotHelper.jl

"""
    with_autoprecompilation_disabled(f::Function)

Helper function to disable precompilation during Pkg operations
"""
function with_autoprecompilation_disabled(f::Function)
    withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
        return f()
    end
end
