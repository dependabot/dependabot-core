# Package discovery and metadata functions for DependabotHelper.jl

# Cache for GeneralMetadata.jl API responses
# Key: package name, Value: Dict of version => registration date
const GENERAL_METADATA_CACHE = Dict{String, Dict{String, Any}}()

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
    get_latest_version(args::AbstractDict)

Args wrapper for get_latest_version function with UUID requirement
"""
function get_latest_version(args::AbstractDict)
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
function get_package_metadata(args::AbstractDict)
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
function fetch_package_versions(args::AbstractDict)
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
function fetch_package_info(args::AbstractDict)
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
function find_package_source_url(args::AbstractDict)
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
function get_available_versions(args::AbstractDict)
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
For packages in the General registry, fetches registration dates from GeneralMetadata.jl API.
"""
function get_version_release_date(package_name::String, version::String, package_uuid::String)
    try
        # First verify the package and version exist
        versions_result = get_available_versions(package_name, package_uuid)
        if haskey(versions_result, "error")
            return versions_result
        end

        available_versions = versions_result["versions"]
        if !(version in available_versions)
            return Dict("error" => "Version $version not found for package $package_name")
        end

        # Check if package is in the General registry
        in_general = is_package_in_general_registry(package_name, package_uuid)

        if in_general
            # Fetch version registration date from GeneralMetadata.jl API
            release_date = fetch_general_registry_release_date(package_name, version)
            return Dict("release_date" => release_date)
        else
            # Package not in General registry, no release date available
            return Dict("release_date" => nothing)
        end

    catch e
        @error "get_version_release_date: Failed to fetch version release date" package_name=package_name version=version exception=(e, catch_backtrace())
        return Dict("error" => "Failed to fetch version release date: $(sprint(showerror, e))")
    end
end

"""
    is_package_in_general_registry(package_name::String, package_uuid::String)

Check if a package is registered in the General registry.
"""
function is_package_in_general_registry(package_name::String, package_uuid::String)
    try
        for reg in Pkg.Registry.reachable_registries()
            # Check if this is the General registry
            if reg.name == "General"
                for (uuid, entry) in reg.pkgs
                    if entry.name == package_name && string(uuid) == package_uuid
                        return true
                    end
                end
            end
        end
        return false
    catch e
        @error "is_package_in_general_registry: Failed to check registry" package_name=package_name package_uuid=package_uuid exception=(e, catch_backtrace())
        return false
    end
end

"""
    fetch_general_registry_release_date(package_name::String, version::String)

Fetch the registration date for a specific version from GeneralMetadata.jl API.
Returns an ISO 8601 datetime string or nothing if not available.
Uses a session-level cache to avoid redundant API calls during batch operations.
"""
function fetch_general_registry_release_date(package_name::String, version::String)
    try
        # Fetch and cache package data if not already present
        cached_data = get!(GENERAL_METADATA_CACHE, package_name) do
            url = "https://juliaregistries.github.io/GeneralMetadata.jl/api/$package_name/versions.json"
            temp_file = Downloads.download(url)
            json_content = read(temp_file, String)
            rm(temp_file; force=true)
            JSON.parse(json_content)
        end

        # Look up the version from cache
        if cached_data isa AbstractDict && haskey(cached_data, version)
            version_info = cached_data[version]
            if version_info isa AbstractDict && haskey(version_info, "registered")
                return string(version_info["registered"])
            end
        end

        return nothing

    catch e
        @error "fetch_general_registry_release_date: Failed to fetch from GeneralMetadata.jl" package_name=package_name version=version exception=(e, catch_backtrace())
        return nothing
    end
end# Args wrapper for get_version_release_date function with UUID requirement
function get_version_release_date(args::AbstractDict)
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

# ============================================================================
# BATCH OPERATIONS
# ============================================================================

"""
    batch_get_package_info(packages::Vector{Dict{String,String}})

Batch operation to get comprehensive package information for multiple packages
in a single Julia process call. This significantly reduces the overhead of
spawning multiple Julia processes.

Expected format for packages:
[
    {"name" => "Tables", "uuid" => "bd369af6-aec1-5ad0-b16a-f7cc5008161c"},
    {"name" => "DataFrames", "uuid" => "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"}
]

Returns a dictionary with package names as keys and their info as values.
"""
function batch_get_package_info(packages::Vector{Dict{String,String}})
    results = Dict{String, Any}()

    for pkg in packages
        pkg_name = get(pkg, "name", "")
        pkg_uuid = get(pkg, "uuid", "")

        if isempty(pkg_name) || isempty(pkg_uuid)
            results[pkg_name] = Dict("error" => "Missing package name or uuid")
            continue
        end

        # Gather all information in one pass
        pkg_info = Dict{String, Any}()

        # Get available versions
        versions_result = get_available_versions(pkg_name, pkg_uuid)
        if haskey(versions_result, "error")
            pkg_info["available_versions"] = Dict("error" => versions_result["error"])
        else
            pkg_info["available_versions"] = versions_result["versions"]
        end

        # Get latest version
        latest_result = get_latest_version(pkg_name, pkg_uuid)
        if haskey(latest_result, "error")
            pkg_info["latest_version"] = Dict("error" => latest_result["error"])
        else
            pkg_info["latest_version"] = latest_result["version"]
        end

        # Get metadata
        metadata_result = get_package_metadata(pkg_name, pkg_uuid)
        if !haskey(metadata_result, "error")
            pkg_info["metadata"] = metadata_result
        end

        results[pkg_name] = pkg_info
    end

    return results
end

# Args wrapper for batch_get_package_info
function batch_get_package_info(args::AbstractDict)
    packages_raw = get(args, "packages", Vector{Any}())

    if isempty(packages_raw)
        return Dict("error" => "No packages provided")
    end

    # JSON v1 parses objects as Dict{String,Any} and arrays as Vector{Any}
    # Convert to the strongly-typed format expected by the core function
    packages = Vector{Dict{String,String}}()
    for pkg in packages_raw
        # Accept any AbstractDict type (handles both Dict and JSON.Object)
        if pkg isa AbstractDict
            push!(packages, Dict{String,String}(
                "name" => string(get(pkg, "name", "")),
                "uuid" => string(get(pkg, "uuid", ""))
            ))
        end
    end

    if isempty(packages)
        return Dict("error" => "No valid packages provided")
    end

    return batch_get_package_info(packages)
end

"""
    batch_get_version_release_dates(packages_versions::Vector{Dict{String,Any}})

Batch operation to get release dates for multiple versions of multiple packages
in a single Julia process call.

Expected format for packages_versions:
[
    {
        "name" => "Tables",
        "uuid" => "bd369af6-aec1-5ad0-b16a-f7cc5008161c",
        "versions" => ["1.0.0", "1.1.0", "1.2.0"]
    },
    {
        "name" => "DataFrames",
        "uuid" => "a93c6f00-e57d-5684-b7b6-d8193f3e46c0",
        "versions" => ["0.21.0", "0.22.0", "1.0.0"]
    }
]

Returns a nested dictionary with package names as keys and version->date mappings.
"""
function batch_get_version_release_dates(packages_versions::Vector{Dict{String,Any}})
    results = Dict{String, Any}()

    for pkg_ver in packages_versions
        pkg_name = get(pkg_ver, "name", "")
        pkg_uuid = get(pkg_ver, "uuid", "")
        versions = get(pkg_ver, "versions", String[])

        if isempty(pkg_name) || isempty(pkg_uuid)
            results[pkg_name] = Dict("error" => "Missing package name or uuid")
            continue
        end

        dates = Dict{String, Any}()
        for version in versions
            date_result = get_version_release_date(pkg_name, version, pkg_uuid)
            if haskey(date_result, "error")
                # Don't fail the whole batch for individual errors
                dates[version] = Dict("error" => date_result["error"])
            else
                dates[version] = date_result["release_date"]
            end
        end
        results[pkg_name] = dates
    end

    return results
end

# Args wrapper for batch_get_version_release_dates
function batch_get_version_release_dates(args::AbstractDict)
    packages_versions_raw = get(args, "packages_versions", Vector{Any}())

    if isempty(packages_versions_raw)
        return Dict("error" => "No packages_versions provided")
    end

    # JSON v1 parses objects as Dict{String,Any} and arrays as Vector{Any}
    # Convert to the strongly-typed format expected by the core function
    packages_versions = Vector{Dict{String,Any}}()
    for pkg_ver in packages_versions_raw
        # Accept any AbstractDict type (handles both Dict and JSON.Object)
        if pkg_ver isa AbstractDict
            versions_raw = get(pkg_ver, "versions", Vector{Any}())
            versions = [string(v) for v in versions_raw]

            push!(packages_versions, Dict{String,Any}(
                "name" => string(get(pkg_ver, "name", "")),
                "uuid" => string(get(pkg_ver, "uuid", "")),
                "versions" => versions
            ))
        end
    end

    if isempty(packages_versions)
        return Dict("error" => "No valid packages_versions provided")
    end

    return batch_get_version_release_dates(packages_versions)
end

"""
    batch_get_available_versions(packages::Vector{Dict{String,String}})

Batch operation to get available versions for multiple packages in a single call.

Expected format for packages:
[
    {"name" => "Tables", "uuid" => "bd369af6-aec1-5ad0-b16a-f7cc5008161c"},
    {"name" => "DataFrames", "uuid" => "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"}
]

Returns a dictionary with package names as keys and version arrays as values.
"""
function batch_get_available_versions(packages::Vector{Dict{String,String}})
    results = Dict{String, Any}()

    for pkg in packages
        pkg_name = get(pkg, "name", "")
        pkg_uuid = get(pkg, "uuid", "")

        if isempty(pkg_name) || isempty(pkg_uuid)
            results[pkg_name] = Dict("error" => "Missing package name or uuid")
            continue
        end

        versions_result = get_available_versions(pkg_name, pkg_uuid)
        results[pkg_name] = versions_result
    end

    return results
end

# Args wrapper for batch_get_available_versions
function batch_get_available_versions(args::AbstractDict)
    packages_raw = get(args, "packages", Vector{Any}())

    if isempty(packages_raw)
        return Dict("error" => "No packages provided")
    end

    # JSON v1 parses objects as Dict{String,Any} and arrays as Vector{Any}
    # Convert to the strongly-typed format expected by the core function
    packages = Vector{Dict{String,String}}()
    for pkg in packages_raw
        # Accept any AbstractDict type (handles both Dict and JSON.Object)
        if pkg isa AbstractDict
            push!(packages, Dict{String,String}(
                "name" => string(get(pkg, "name", "")),
                "uuid" => string(get(pkg, "uuid", ""))
            ))
        end
    end

    if isempty(packages)
        return Dict("error" => "No valid packages provided")
    end

    return batch_get_available_versions(packages)
end
