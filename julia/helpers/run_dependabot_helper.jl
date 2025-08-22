#!/usr/bin/env julia

# Main entry point for Ruby to call DependabotHelper.jl functions
# Expects JSON input via STDIN and outputs JSON result

using DependabotHelper

# Run the helper
DependabotHelper.run()
