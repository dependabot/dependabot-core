"""
Custom registry management functionality for DependabotHelper.jl
Handles Git-based custom Julia registries following Julia's standard patterns.
"""

using Pkg

"""
    add_custom_registries(registry_urls::Vector{String})

Add custom registries if they don't already exist (idempotent operation).
Checks if registries are already added to avoid duplicate registry errors.
"""
function add_custom_registries(registry_urls::Vector{String})
    for url in registry_urls
        # Check if already added to avoid duplicate registry errors
        existing = Pkg.Registry.reachable_registries()
        # Check if registry with this URL already exists
        # Note: Registry URLs are stored in the path field, not url
        already_exists = false
        for reg in existing
            try
                # Try to check if this registry corresponds to our URL
                # This is a simplified check - in practice Julia manages this internally
                if reg.name != "General" && occursin(basename(url), reg.path)
                    already_exists = true
                    break
                end
            catch
                # If we can't determine, just skip the check
                continue
            end
        end

        if !already_exists
            try
                Pkg.Registry.add(RegistrySpec(url=url))
                @info "Successfully added registry: $url"
            catch e
                @error "Failed to add registry $url: $(e.msg)"
                rethrow(e)
            end
        else
            @info "Registry already exists: $url"
        end
    end
end

"""
    update_registries()

Update all registered registries to get latest package information.
This should be called periodically to ensure we have the latest package versions.
"""
function update_registries()
    try
        Pkg.Registry.update()
        @info "Successfully updated all registries"
    catch e
        @error "Failed to update registries: $(e.msg)"
        rethrow(e)
    end
end

"""
    resolve_dependencies_with_custom_registries(project_toml_path::String, registry_urls::Vector{String})

Resolve dependencies using custom registries.
First ensures custom registries are available, then resolves dependencies.
"""
function resolve_dependencies_with_custom_registries(project_toml_path::String, registry_urls::Vector{String})
    # First ensure custom registries are available
    add_custom_registries(registry_urls)

    # Update registries to get latest package information
    update_registries()

    # Activate project and resolve dependencies
    Pkg.activate(dirname(project_toml_path))

    try
        Pkg.resolve()

        # Return resolved manifest information using Pkg's Context
        Pkg.activate(dirname(project_toml_path)) do
            ctx = Pkg.Types.Context()
            if isfile(ctx.env.manifest_file)
                # Use the existing parse_manifest functionality to get structured data
                return parse_manifest(Dict("manifest_path" => ctx.env.manifest_file))
            end
        end

        return Dict()
    catch e
        @error "Dependency resolution failed: $(e.msg)"
        rethrow(e)
    end
end

"""
    list_available_registries()

List all currently available registries for debugging.
Returns array of tuples with (name, url) for each registry.
"""
function list_available_registries()
    registries = Pkg.Registry.reachable_registries()
    return [(reg.name, reg.path) for reg in registries]
end

"""
    manage_registry_state(registry_urls::Vector{String})

Handle persistent Julia depot state and comprehensive error scenarios.
Combines registry addition and updates with proper error handling.
"""
function manage_registry_state(registry_urls::Vector{String})
    try
        # Add any missing registries
        add_custom_registries(registry_urls)

        # Periodic registry updates to get latest package information
        update_registries()

        return true
    catch e
        if e isa Pkg.Types.GitError
            @error "Git authentication or network error: $(e.msg)"
        elseif e isa Pkg.Types.RegistryError
            @error "Registry format or compatibility error: $(e.msg)"
        else
            @error "Unknown error managing registries: $(e.msg)"
        end

        # For debugging, list currently available registries
        @info "Currently available registries:"
        for reg in Pkg.Registry.reachable_registries()
            @info "  - $(reg.name): $(reg.path)"
        end

        rethrow(e)
    end
end

"""
    get_latest_version_with_custom_registries(package_name::String, package_uuid::String, registry_urls::Vector{String})

Get the latest version of a package using custom registries.
Ensures custom registries are available before checking for latest version.
"""
function get_latest_version_with_custom_registries(package_name::String, package_uuid::String, registry_urls::Vector{String})
    # Ensure custom registries are available
    manage_registry_state(registry_urls)

    # Now use the existing get_latest_version functionality
    return get_latest_version(Dict("package_name" => package_name, "package_uuid" => package_uuid))
end

"""
    get_available_versions_with_custom_registries(package_name::String, package_uuid::String, registry_urls::Vector{String})

Get all available versions of a package using custom registries.
Ensures custom registries are available before checking for versions.
"""
function get_available_versions_with_custom_registries(package_name::String, package_uuid::String, registry_urls::Vector{String})
    # Ensure custom registries are available
    manage_registry_state(registry_urls)

    # Now use the existing get_available_versions functionality
    return get_available_versions(Dict("package_name" => package_name, "package_uuid" => package_uuid))
end
