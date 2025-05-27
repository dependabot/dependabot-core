#!/usr/bin/env julia

# TODO: use this as a proper package for speed
# Load the helper module
include(joinpath(@__DIR__, "src", "DependabotHelper.jl"))

using .DependabotHelper

# Run the helper
DependabotHelper.run()
