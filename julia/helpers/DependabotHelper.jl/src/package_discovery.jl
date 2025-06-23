# Package discovery and metadata functions for DependabotHelper.jl

"""
    get_latest_version(package_name::String, package_uuid::String)

Get the latest version using Pkg registry directly with UUID for precise identification.
"""
function get_latest_version(package_name::String, package_uuid::String)
    try
        # Search all registries for the package
        for reg in Pkg.Registry.reachable_registries()
            for (uuid, entry) in reg.pkgs
                name_matches = entry.name == package_name
                uuid_matches = string(uuid) == package_uuid

                if name_matches && uuid_matches
                    # Get versions from the registry, excluding yanked ones
                    versions = Pkg.Registry.registry_info(entry).version_info
                    if !isempty(versions)
                        # Filter out yanked versions
                        non_yanked_versions = [ver for (ver, info) in versions if !info.yanked]

                        if !isempty(non_yanked_versions)
                            latest_version = maximum(non_yanked_versions)
                            return Dict("version" => string(latest_version), "package_uuid" => string(uuid))
                        else
                            # All versions are yanked
                            uuid_info = " [$package_uuid]"
                            return Dict("error" => "All versions of package $package_name$uuid_info are yanked")
                        end
                    end
                end
            end
        end

        uuid_info = " [$package_uuid]"
        return Dict("error" => "Package $package_name$uuid_info not found in registry")
    catch ex
        @error "get_latest_version: Failed to get latest version" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to get latest version: $(sprint(showerror, ex))")
    end
end

"""
    get_latest_version(args::Dict)

Args wrapper for get_latest_version function with UUID requirement
"""
function get_latest_version(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return get_latest_version(package_name, package_uuid)
end

"""
    get_package_metadata(package_name::String, package_uuid::String)

Get comprehensive metadata for a package using both name and UUID.
"""
function get_package_metadata(package_name::String, package_uuid::String)
    try
        # Search all registries for the package
        for reg in Pkg.Registry.reachable_registries()
            for (uuid, entry) in reg.pkgs
                if entry.name == package_name && string(uuid) == package_uuid
                    reg_info = Pkg.Registry.registry_info(entry)

                    # Get available versions
                    versions = [string(v) for v in keys(reg_info.version_info)]
                    latest_version = string(maximum(keys(reg_info.version_info)))

                    return Dict(
                        "name" => package_name,
                        "uuid" => string(uuid),
                        "latest_version" => latest_version,
                        "available_versions" => versions
                    )
                end
            end
        end

        return Dict("error" => "Package $package_name [$package_uuid] not found in registry")
    catch ex
        @error "get_package_metadata: Failed to get package metadata" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to get package metadata: $(sprint(showerror, ex))")
    end
end

# Args wrapper for get_package_metadata function with optional UUID
function get_package_metadata(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return get_package_metadata(package_name, package_uuid)
end

"""
    fetch_package_versions(package_name::String, package_uuid::String)

Fetch all available versions for a package using both name and UUID for precise identification.
UUID is required to ensure correct package identification.
"""
function fetch_package_versions(package_name::String, package_uuid::String)
    try
        versions = String[]

        # Search all registries for the package with exact UUID match
        for reg in Pkg.Registry.reachable_registries()
            for (uuid, entry) in reg.pkgs
                name_matches = entry.name == package_name
                uuid_matches = string(uuid) == package_uuid

                if name_matches && uuid_matches
                    version_info = Pkg.Registry.registry_info(entry).version_info
                    versions = [string(v) for v in keys(version_info)]
                    break
                end
            end
            if !isempty(versions)
                break
            end
        end

        if isempty(versions)
            return Dict("error" => "No versions found for package $package_name [$package_uuid]")
        end

        # Sort versions
        try
            version_numbers = [Pkg.Types.VersionNumber(v) for v in versions]
            sorted_versions = sort(version_numbers)
            versions = [string(v) for v in sorted_versions]
        catch
            # If version parsing fails, keep original order
        end

        return Dict(
            "package_name" => package_name,
            "package_uuid" => package_uuid,
            "versions" => versions,
            "latest_version" => last(versions),
            "total_versions" => length(versions)
        )
    catch ex
        @error "fetch_package_versions: Failed to fetch package versions" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to fetch package versions: $(sprint(showerror, ex))")
    end
end

# Args wrapper for fetch_package_versions function with UUID requirement
function fetch_package_versions(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return fetch_package_versions(package_name, package_uuid)
end

"""
    fetch_package_info(package_name::String, package_uuid::String)

Fetch basic information about a package from the registry using both name and UUID for precise identification.
UUID is required to ensure correct package identification.
"""
function fetch_package_info(package_name::String, package_uuid::String)
    try
        # Search all registries for the package with exact UUID match
        for reg in Pkg.Registry.reachable_registries()
            for (uuid, entry) in reg.pkgs
                name_matches = entry.name == package_name
                uuid_matches = string(uuid) == package_uuid

                if name_matches && uuid_matches
                    reg_info = Pkg.Registry.registry_info(entry)

                    # Get all versions
                    all_versions = [string(v) for v in keys(reg_info.version_info)]

                    # Sort versions
                    try
                        version_numbers = [Pkg.Types.VersionNumber(v) for v in all_versions]
                        sorted_versions = sort(version_numbers)
                        all_versions = [string(v) for v in sorted_versions]
                    catch
                        # If version parsing fails, keep original order
                    end

                    # Get the latest version info
                    latest_version = maximum(keys(reg_info.version_info))
                    latest_info = reg_info.version_info[latest_version]

                    return Dict(
                        "name" => package_name,
                        "uuid" => string(uuid),
                        "latest_version" => string(latest_version),
                        "tree_hash" => string(latest_info.git_tree_sha1),
                        "registry_path" => entry.path,
                        "all_versions" => all_versions
                    )
                end
            end
        end

        return Dict("error" => "Package $package_name [$package_uuid] not found in registry")
    catch ex
        @error "fetch_package_info: Failed to fetch package info" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to fetch package info: $(sprint(showerror, ex))")
    end
end

# Args wrapper for fetch_package_info function with UUID requirement
function fetch_package_info(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return fetch_package_info(package_name, package_uuid)
end

"""
    find_package_source_url(package_name::String, package_uuid::String)

Find the source URL for a package using both name and UUID for precise identification.
Julia packages are uniquely identified by both name and UUID since multiple packages
in different registries could have the same name.
"""
function find_package_source_url(package_name::String, package_uuid::String)
    try
        # Only use registry info for authoritative source URLs
        registry_url = source_url_from_registry(package_name, package_uuid)
        if !haskey(registry_url, "error") && !isempty(registry_url["source_url"])
            return registry_url
        end

        return Dict("error" => "Could not find source URL for package $package_name [$package_uuid]")
    catch ex
        @error "find_package_source_url: Failed to find source URL" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to find source URL: $(sprint(showerror, ex))")
    end
end

# Args wrapper for find_package_source_url function with UUID requirement
function find_package_source_url(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return find_package_source_url(package_name, package_uuid)
end

"""
    source_url_from_registry(package_name::String, package_uuid::String)

Get source URL from package registry information using both name and UUID for precise identification.
"""
function source_url_from_registry(package_name::String, package_uuid::String)
    try
        registries = Pkg.Registry.reachable_registries()

        for reg in registries
            for (uuid, entry) in reg.pkgs
                # Match by name first, then by UUID if provided
                if entry.name == package_name
                    uuid_to_check = string(uuid)
                    if uuid_to_check != package_uuid
                        continue  # Skip this entry if UUID doesn't match
                    end

                    reg_info = Pkg.Registry.registry_info(entry)

                    # Get repository URL from PkgInfo.repo field
                    if reg_info.repo !== nothing && !isempty(reg_info.repo)
                        return Dict(
                            "source_url" => reg_info.repo,
                            "source_type" => detect_source_type(reg_info.repo),
                            "package_uuid" => string(uuid)  # Include UUID in response
                        )
                    end

                    # If we found a matching name and UUID (or no UUID was provided),
                    # but no repo URL, we can stop looking
                    break
                end
            end
        end

        uuid_info = " [$package_uuid]"
        return Dict("error" => "No registry source URL found for $package_name$uuid_info")
    catch ex
        @error "source_url_from_registry: Failed to get source URL from registry" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Registry lookup failed: $(sprint(showerror, ex))")
    end
end

"""
    detect_source_type(url::String)

Detect the type of source repository from URL
"""
function detect_source_type(url::String)
    url = lowercase(url)
    if occursin("github.com", url)
        return "github"
    elseif occursin("gitlab.com", url)
        return "gitlab"
    elseif occursin("bitbucket.org", url)
        return "bitbucket"
    else
        return "git"
    end
end

"""
    extract_package_metadata_from_url(package_name::String, source_url::String)

Extract additional metadata from a package's source URL
"""
function extract_package_metadata_from_url(package_name::String, source_url::String)
    try
        source_type = detect_source_type(source_url)

        metadata = Dict{String,Any}(
            "package_name" => package_name,
            "source_url" => source_url,
            "source_type" => source_type
        )

        # Extract owner and repo from GitHub/GitLab URLs
        if source_type in ["github", "gitlab"]
            # Pattern: https://github.com/owner/repo.git
            patterns = [
                r"(?:https?://)?(?:www\.)?(?:github|gitlab)\.com/([^/]+)/([^/\.]+)(?:\.git)?",
                r"git@(?:github|gitlab)\.com:([^/]+)/([^/\.]+)(?:\.git)?"
            ]

            for pattern in patterns
                match = Base.match(pattern, source_url)
                if match !== nothing
                    metadata["owner"] = match.captures[1]
                    metadata["repo"] = match.captures[2]
                    break
                end
            end
        end

        return metadata
    catch ex
        @error "extract_package_metadata_from_url: Failed to extract metadata from URL" package_name=package_name source_url=source_url exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to extract metadata from URL: $(sprint(showerror, ex))")
    end
end

"""
    get_available_versions(package_name::String, package_uuid::String)

Get all available versions for a package from the registry using both name and UUID for precise identification.
Returns just the version strings in sorted order.
"""
function get_available_versions(package_name::String, package_uuid::String)
    try
        versions = String[]

        # Search all registries for the package with exact UUID match
        for reg in Pkg.Registry.reachable_registries()
            for (uuid, entry) in reg.pkgs
                name_matches = entry.name == package_name
                uuid_matches = string(uuid) == package_uuid

                if name_matches && uuid_matches
                    version_info = Pkg.Registry.registry_info(entry).version_info
                    versions = [string(v) for v in keys(version_info)]
                    break
                end
            end
            if !isempty(versions)
                break
            end
        end

        if isempty(versions)
            return Dict("error" => "No versions found for package $package_name [$package_uuid]")
        end

        # Sort versions
        try
            version_numbers = [Pkg.Types.VersionNumber(v) for v in versions]
            sorted_versions = sort(version_numbers)
            versions = [string(v) for v in sorted_versions]
        catch
            # If version parsing fails, keep original order
        end

        return Dict("versions" => versions)
    catch ex
        @error "get_available_versions: Failed to fetch available versions" package_name=package_name package_uuid=package_uuid exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to fetch available versions: $(sprint(showerror, ex))")
    end
end

# Args wrapper for get_available_versions function with UUID requirement
function get_available_versions(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return get_available_versions(package_name, package_uuid)
end

"""
    get_version_release_date(package_name::String, version::String, package_uuid::String)

Get the release date for a specific version of a package.
Note: Julia registries don't typically store release dates, so this attempts to
get the information from the git repository if available.
"""
function get_version_release_date(package_name::String, version::String, package_uuid::String)
    try
        # Julia registries don't store release dates directly
        # We could potentially fetch this from the git repository, but for now
        # we'll return a placeholder that indicates the limitation

        # First verify the package and version exist
        versions_result = get_available_versions(package_name, package_uuid)
        if haskey(versions_result, "error")
            return versions_result
        end

        available_versions = versions_result["versions"]
        if !(version in available_versions)
            return Dict("error" => "Version $version not found for package $package_name")
        end

        # For now, return nil since Julia registries don't store release dates
        # In a future enhancement, this could attempt to fetch from the git repository
        return Dict("release_date" => nothing)

    catch e
        return Dict("error" => "Failed to fetch version release date: $(sprint(showerror, e))")
    end
end

# Args wrapper for get_version_release_date function with UUID requirement
function get_version_release_date(args::Dict)
    package_name = get(args, "package_name", "")
    version = get(args, "version", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(version)
        return Dict("error" => "Both package_name and version are required")
    end

    return get_version_release_date(package_name, version, package_uuid)
end

"""
    get_resolved_dependency_info()

Get information about resolved dependencies in the current environment
"""
function get_resolved_dependency_info()
    try
        deps = Pkg.dependencies()
        dependency_info = Dict{String,Any}()

        for (uuid, dep) in deps
            if !isnothing(dep.version)
                dependency_info[dep.name] = Dict(
                    "name" => dep.name,
                    "uuid" => string(uuid),
                    "version" => string(dep.version),
                    "source" => dep.source,
                    "is_tracking_path" => dep.is_tracking_path,
                    "is_tracking_repo" => dep.is_tracking_repo,
                    "is_tracking_registry" => dep.is_tracking_registry
                )
            end
        end

        return dependency_info
    catch e
        return Dict("error" => "Failed to get dependency info: $(sprint(showerror, e))")
    end
end
