"""
Custom registry management functionality for DependabotHelper.jl
Handles Git-based custom Julia registries following Julia's standard patterns.
"""

using Pkg

"""
    normalize_registry_url(url)

Normalize a registry URL for comparison: case-insensitive, ignoring a
trailing ".git" suffix and trailing slashes.
"""
function normalize_registry_url(url::AbstractString)
    return lowercase(rstrip(replace(String(url), r"\.git$" => ""), '/'))
end

"""
    add_custom_registries(registry_urls::Vector{String})

Add custom registries if they don't already exist (idempotent operation).
Checks if registries are already added to avoid duplicate registry errors.
"""
function add_custom_registries(registry_urls::Vector{String})
    for url in registry_urls
        # Compare against the URL each installed registry was cloned from.
        # (The old check matched basename(url) as a substring of the depot
        # path, which never matched ".git" URLs and could false-positive on
        # unrelated registries.)
        already_exists = any(Pkg.Registry.reachable_registries()) do reg
            repo = try
                reg.repo
            catch
                nothing
            end
            repo !== nothing && normalize_registry_url(repo) == normalize_registry_url(url)
        end

        if !already_exists
            try
                Pkg.Registry.add(RegistrySpec(url=url))
                @info "Successfully added registry: $url"
            catch e
                @error "Failed to add registry $url: $(sprint(showerror, e))"
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
        @error "Failed to update registries: $(sprint(showerror, e))"
        rethrow(e)
    end
end

# How long a registry update stays fresh. Production containers are
# ephemeral, so in practice this means one update per job.
const REGISTRY_UPDATE_TTL_SECONDS = 60 * 60

"""
    ensure_registries_fresh()

Refresh all installed registries at most once per REGISTRY_UPDATE_TTL_SECONDS
(tracked by a marker file in the depot). Version discovery otherwise reads
whatever registry state was baked into the Docker image at build time, so new
releases would be invisible until the image is rebuilt. A failed refresh is
logged but never fails the lookup — stale data is better than none. Set
DEPENDABOT_SKIP_REGISTRY_UPDATE=1 to disable (used by the test suite).
"""
function ensure_registries_fresh()
    get(ENV, "DEPENDABOT_SKIP_REGISTRY_UPDATE", "") == "1" && return

    try
        registries_dir = joinpath(first(Base.DEPOT_PATH), "registries")
        isdir(registries_dir) || mkpath(registries_dir)
        marker = joinpath(registries_dir, ".dependabot_registry_updated")
        if isfile(marker) && time() - mtime(marker) < REGISTRY_UPDATE_TTL_SECONDS
            return
        end

        Pkg.Registry.update()
        touch(marker)
    catch e
        @warn "Registry refresh failed; using existing registry state" exception=(e, catch_backtrace())
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
        @error "Failed to manage registries: $(sprint(showerror, e))"

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
