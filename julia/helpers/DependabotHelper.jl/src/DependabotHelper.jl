module DependabotHelper

import JSON
import Pkg
using PrecompileTools

# Include all the logical function modules
include("utilities.jl")
include("project_parsing.jl")
include("version_constraints.jl")
include("package_discovery.jl")
include("dependency_resolution.jl")
include("registry_management.jl")

# Main entry point that processes the input JSON and calls the appropriate function
function run()
    input = readline()
    result = run(input)
    println(result)

    # Exit with error code if there was an error
    parsed_result = JSON.parse(result)
    if haskey(parsed_result, "error")
        exit(1)
    end
end

function run(input::String)
    result = try
        input = JSON.parse(input)
        func_name = input["function"]
        args = input["args"]

        # Project and manifest operations (core parsing)
        function_result = if func_name == "parse_project"
            parse_project(args["project_path"], get(args, "manifest_path", nothing))
        elseif func_name == "parse_manifest"
            parse_manifest(args)
        elseif func_name == "get_version_from_manifest"
            get_version_from_manifest(args["manifest_path"], args["name"], args["uuid"])
        elseif func_name == "update_manifest"
            update_manifest(args)

        # Version and constraint operations
        elseif func_name == "parse_julia_version_constraint"
            parse_julia_version_constraint(args["constraint"])
        elseif func_name == "check_version_satisfies_constraint"
            check_version_satisfies_constraint(args["version"], args["constraint"])
        elseif func_name == "expand_version_constraint"
            expand_version_constraint(args["constraint"])

        # Package discovery and metadata
        elseif func_name == "get_latest_version"
            get_latest_version(args)
        elseif func_name == "get_package_metadata"
            get_package_metadata(args)
        elseif func_name == "get_available_versions"
            get_available_versions(args)
        elseif func_name == "get_version_release_date"
            get_version_release_date(args)
        elseif func_name == "fetch_package_versions"
            fetch_package_versions(args)
        elseif func_name == "fetch_package_info"
            fetch_package_info(args)
        elseif func_name == "find_package_source_url"
            find_package_source_url(args)
        elseif func_name == "extract_package_metadata_from_url"
            extract_package_metadata_from_url(args["package_name"], args["source_url"])

        # Dependency resolution and compatibility checking
        elseif func_name == "check_update_compatibility"
            check_update_compatibility(args["project_path"], args["package_name"], args["target_version"])
        elseif func_name == "resolve_dependencies_with_constraints"
            resolve_dependencies_with_constraints(args["project_path"], args["target_updates"])

        # Custom registry management
        elseif func_name == "add_custom_registries"
            add_custom_registries(Vector{String}(args["registry_urls"]))
        elseif func_name == "update_registries"
            update_registries()
        elseif func_name == "resolve_dependencies_with_custom_registries"
            resolve_dependencies_with_custom_registries(args["project_toml_path"], Vector{String}(args["registry_urls"]))
        elseif func_name == "list_available_registries"
            list_available_registries()
        elseif func_name == "manage_registry_state"
            manage_registry_state(Vector{String}(args["registry_urls"]))
        elseif func_name == "get_latest_version_with_custom_registries"
            get_latest_version_with_custom_registries(args["package_name"], args["package_uuid"], Vector{String}(args["registry_urls"]))
        elseif func_name == "get_available_versions_with_custom_registries"
            get_available_versions_with_custom_registries(args["package_name"], args["package_uuid"], Vector{String}(args["registry_urls"]))
        else
            Dict("error" => "Unknown function: $func_name")
        end

        # Check if the function result itself contains an error
        if isa(function_result, Dict) && haskey(function_result, "error")
            function_result
        else
            Dict("result" => function_result)
        end
    catch err
        Dict(
            "error" => string(err),
            "error_class" => string(typeof(err))
        )
    end
    return JSON.json(result)
end

include("precompile.jl")

end # module
