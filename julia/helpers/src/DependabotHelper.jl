module DependabotHelper

import JSON
import Pkg

include("functions.jl")

# Main entry point that processes the input JSON and calls the appropriate function
function run()
    input = JSON.parse(readline())

    result = try
        func_name = input["function"]
        args = input["args"]

        if func_name == "parse_project"
            parse_project(args)
        elseif func_name == "get_latest_version"
            get_latest_version(args)
        elseif func_name == "update_manifest"
            update_manifest(args)
        else
            error("Unknown function: $func_name")
        end

        Dict("result" => result)
    catch err
        Dict(
            "error" => string(err),
            "error_class" => string(typeof(err)),
            "trace" => string.(stacktrace(catch_backtrace()))
        )
    end

    println(JSON.json(result))
end

end # module
