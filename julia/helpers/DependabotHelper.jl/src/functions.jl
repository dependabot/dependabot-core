# All helper functions for working with Julia dependencies

# ============================================================================
# CORE UTILITY FUNCTIONS
# ============================================================================

"""
    with_autoprecompilation_disabled(f::Function)

Helper function to disable precompilation during Pkg operations
"""
function with_autoprecompilation_disabled(f::Function)
    withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
        return f()
    end
end

# ============================================================================
# PROJECT AND MANIFEST PARSING (Core Operations)
# ============================================================================

"""
    parse_project(project_path::String, manifest_path::Union{String,Nothing}=nothing)

Parse a Julia project file and return comprehensive project information.
"""
function parse_project(project_path::String, manifest_path::Union{String,Nothing}=nothing)
    try
        # Determine if project_path is a directory or file
        project_dir = if isdir(project_path)
            project_path
        elseif isfile(project_path)
            dirname(project_path)
        else
            return Dict("error" => "Invalid project path: $project_path")
        end

        # Use Pkg to load the project
        original_env = Base.active_project()
        try
            Pkg.activate(project_dir; io=devnull)
            ctx = Pkg.Types.Context()

            if !samefile(ctx.env.project_file, project_path)
                return Dict("error" => "Project file found by Julia ($(ctx.env.project_file)) is not the same file as the specified file: $project_path")
            end

            # Get project information
            project_info = ctx.env.project

            # Extract basic information
            name = project_info.name
            version = string(project_info.version)
            uuid = string(project_info.uuid)

            # Get manifest information if available
            manifest_info = Dict{String,Any}()
            manifest_file_path = if !isnothing(manifest_path)
                if !samefile(manifest_path, joinpath(project_dir, "Manifest.toml"))
                    return Dict("error" => "Manifest file found by Julia ($(ctx.env.manifest_file)) is not the same file as the specified file: $manifest_path")
                end
                manifest_path
            else
                ctx.env.manifest_file
            end

            manifest_versions = Dict{String,String}()
            if isfile(manifest_file_path)
                manifest_result = parse_manifest(manifest_file_path)
                if !haskey(manifest_result, "error")
                    manifest_info = manifest_result
                    # Extract versions from manifest for lookup
                    for dep in manifest_result["dependencies"]
                        manifest_versions[dep["name"]] = dep["version"]
                    end
                end
            end

            # Get dependencies and add resolved versions
            dependencies = []
            for (dep_name, dep_uuid) in project_info.deps
                dep_info = Dict{String,Any}(
                    "name" => dep_name,
                    "uuid" => string(dep_uuid)
                )

                # Add version constraint if available in compat
                if haskey(project_info.compat, dep_name)
                    compat_spec = project_info.compat[dep_name]
                    # Extract the original constraint string
                    constraint_str = if isa(compat_spec, Pkg.Types.Compat)
                        compat_spec.str  # This should be the original constraint string
                    else
                        string(compat_spec)
                    end
                    dep_info["requirement"] = constraint_str
                else
                    dep_info["requirement"] = "*"
                end

                # Add resolved version from manifest if available
                if haskey(manifest_versions, dep_name)
                    dep_info["resolved_version"] = manifest_versions[dep_name]
                end

                push!(dependencies, dep_info)
            end

            # Get dev-dependencies (extras)
            dev_dependencies = []
            for (dep_name, dep_uuid) in project_info.extras
                dev_dep_info = Dict{String,Any}(
                    "name" => dep_name,
                    "uuid" => string(dep_uuid),
                    "requirement" => "*"
                )
                push!(dev_dependencies, dev_dep_info)
            end

            # Get Julia version requirement
            julia_version = ""
            if haskey(project_info.compat, "julia")
                compat_spec = project_info.compat["julia"]
                julia_version = if isa(compat_spec, Pkg.Types.Compat)
                    compat_spec.str
                else
                    string(compat_spec)
                end
            end

            # Get manifest information if available
            manifest_info = Dict{String,Any}()
            manifest_file_path = if !isnothing(manifest_path)
                manifest_path
            else
                joinpath(project_dir, "Manifest.toml")
            end

            # No additional code needed here - everything is processed above

            return Dict{String,Any}(
                "name" => name,
                "version" => version,
                "uuid" => uuid,
                "julia_version" => julia_version,
                "dependencies" => dependencies,
                "dev_dependencies" => dev_dependencies,
                "manifest" => manifest_info,
                "project_path" => ctx.env.project_file,
                "manifest_path" => manifest_file_path
            )
        finally
            # Restore original environment
            if !isnothing(original_env)
                Pkg.activate(original_env; io=devnull)
            end
        end
    catch e
        return Dict("error" => "Failed to parse project: $(sprint(showerror, e))")
    end
end

"""
    parse_project(args::Dict)

Args wrapper for parse_project function
"""
function parse_project(args::Dict)
    return parse_project(args["project_path"], get(args, "manifest_path", nothing))
end

"""
    parse_manifest(manifest_path::String)

Parse a Julia manifest file and return comprehensive dependency information.
Enhanced version with better error handling and comprehensive metadata.
"""
function parse_manifest(manifest_path::String)
    try
        if !isfile(manifest_path)
            return Dict("error" => "Manifest file not found: $manifest_path")
        end

        # Determine the project directory from manifest path
        project_dir = dirname(manifest_path)

        # Use Pkg to load the manifest
        original_env = Base.active_project()
        try
            Pkg.activate(project_dir; io=devnull)
            ctx = Pkg.Types.Context()

            if !samefile(ctx.env.manifest_file, manifest_path)
                return Dict("error" => "Manifest file found by Julia ($(ctx.env.manifest_file)) is not the same file as the specified file: $manifest_path")
            end

            dependencies = []

            # Get manifest information
            if !isnothing(ctx.env.manifest)
                for (uuid, pkg_entry) in ctx.env.manifest
                    dep_info = Dict{String,Any}(
                        "name" => pkg_entry.name,
                        "uuid" => string(uuid),
                        "version" => pkg_entry.version !== nothing ? string(pkg_entry.version) : "",
                        "tree_hash" => pkg_entry.tree_hash !== nothing ? string(pkg_entry.tree_hash) : "",
                        "repo_url" => pkg_entry.repo.source !== nothing ? string(pkg_entry.repo.source) : "",
                        "repo_rev" => pkg_entry.repo.rev !== nothing ? string(pkg_entry.repo.rev) : "",
                        "path" => pkg_entry.path !== nothing ? string(pkg_entry.path) : ""
                    )

                    # Add dependencies of this package
                    if !isempty(pkg_entry.deps)
                        dep_deps = Dict{String,String}()
                        for (dep_name, dep_uuid) in pkg_entry.deps
                            dep_deps[dep_name] = string(dep_uuid)
                        end
                        dep_info["dependencies"] = dep_deps
                    end

                    push!(dependencies, dep_info)
                end
            end

            return Dict{String,Any}(
                "dependencies" => dependencies,
                "manifest_path" => manifest_path
            )
        finally
            # Restore original environment
            if !isnothing(original_env)
                Pkg.activate(original_env; io=devnull)
            end
        end
    catch e
        return Dict("error" => "Failed to parse manifest: $(sprint(showerror, e))")
    end
end

"""
    parse_manifest(args::Dict)

Args wrapper for parse_manifest function
"""
function parse_manifest(args::Dict)
    return parse_manifest(args["manifest_path"])
end

"""
    get_version_from_manifest(manifest_path::String, name::String, uuid::String)

Get the version of a specific package from the manifest
"""
function get_version_from_manifest(manifest_path::String, name::String, uuid::String)
    try
        manifest_result = parse_manifest(manifest_path)
        if haskey(manifest_result, "error")
            return manifest_result
        end

        dependencies = manifest_result["dependencies"]

        # Look for the package by name and UUID
        for (dep_name, dep_info) in dependencies
            if dep_info["name"] == name && (isempty(uuid) || dep_info["uuid"] == uuid)
                return Dict("version" => dep_info["version"])
            end
        end

        return Dict("error" => "Package $name not found in manifest")
    catch e
        return Dict("error" => "Failed to get version from manifest: $(sprint(showerror, e))")
    end
end

"""
    update_manifest(project_path::String, updates::Dict)

Update the manifest with new package versions.
Enhanced version with better error handling and validation.
"""
function update_manifest(project_path::String, updates::Dict)
    try
        # Validate inputs
        if !isdir(dirname(project_path))
            return Dict("error" => "Project directory does not exist")
        end

        project_file = joinpath(project_path, "Project.toml")
        if !isfile(project_file)
            return Dict("error" => "Project.toml not found in directory")
        end

        # Create a temporary directory for the update operation
        mktempdir() do temp_dir
            # Copy project files to temp directory
            temp_project_file = joinpath(temp_dir, "Project.toml")
            cp(project_file, temp_project_file)

            # Copy manifest if it exists
            manifest_file = joinpath(project_path, "Manifest.toml")
            temp_manifest_file = joinpath(temp_dir, "Manifest.toml")
            if isfile(manifest_file)
                cp(manifest_file, temp_manifest_file)
            end

            # Activate the temporary project
            Pkg.activate(temp_dir) do
                with_autoprecompilation_disabled() do
                    # Process each update
                    pkg_specs = Pkg.PackageSpec[]
                    for (package_name, target_version) in updates
                        push!(pkg_spec, Pkg.PackageSpec(name=package_name, version=target_version))
                    end
                    try
                        # Try to add/update the packages with the specific versions
                        Pkg.add(pkg_specs; io=devnull)
                    catch e
                        return Dict("error" => "Failed to update package(s): $(sprint(showerror, e))")
                    end
                end

                # Read the updated manifest
                if isfile(temp_manifest_file)
                    updated_manifest = parse_manifest(temp_manifest_file)
                    if haskey(updated_manifest, "error")
                        return updated_manifest
                    end

                    # Copy the updated manifest back to the original location
                    cp(temp_manifest_file, manifest_file; force=true)

                    return Dict(
                        "result" => "success",
                        "updated_manifest" => updated_manifest
                    )
                else
                    return Dict("error" => "Updated manifest file not found")
                end
            end
        end
    catch e
        return Dict("error" => "Failed to update manifest: $(sprint(showerror, e))")
    end
end

"""
    update_manifest(args::Dict)

Args wrapper for update_manifest function
"""
function update_manifest(args::Dict)
    return update_manifest(args["project_path"], args["updates"])
end

# ============================================================================
# VERSION CONSTRAINT PARSING AND VALIDATION
# ============================================================================
#
# These functions implement the official Julia Pkg.jl version constraint
# specification as documented at:
# https://pkgdocs.julialang.org/v1/compatibility/#Version-specifier-format
#
# Supported constraint formats:
# - Caret specifiers: ^1.2.3 (allows [1.2.3, 2.0.0))
# - Tilde specifiers: ~1.2.3 (allows [1.2.3, 1.3.0))
# - Inequality specifiers: >=1.2.3, <2.0.0
# - Hyphen specifiers: 1.2.3 - 4.5.6
# - Comma-separated: 1.2, 2
# - Exact versions: 1.2.3
# - Wildcard: * (matches any version)
#
# Special handling for 0.x versions follows semver rules:
# - ^0.2.3 means [0.2.3, 0.3.0)
# - ^0.0.3 means [0.0.3, 0.0.4)
#

"""
    convert_to_julia_constraint(constraint::String)

Convert various constraint formats to Julia-compatible version constraints using semver_spec.

This function handles preprocessing for edge cases that semver_spec doesn't support directly,
such as wildcard (*) constraints and double equals (==) operators.

For standard constraint formats (^, ~, >=, <, hyphen ranges, comma-separated),
the original constraint is returned as-is since semver_spec handles them correctly.
"""
function convert_to_julia_constraint(constraint::String)
    constraint = strip(constraint)

    # Handle empty or wildcard constraints (semver_spec doesn't support these)
    if isempty(constraint) || constraint == "*"
        return "*"
    end

    # Handle double equals (convert to single equals for exact match)
    if startswith(constraint, "==")
        constraint = "=" * constraint[3:end]
    end

    # Try to use Julia's semver_spec which handles:
    # - Caret constraints: ^1.2.3
    # - Tilde constraints: ~1.2.3
    # - Inequality operators: >=1.2.3, <1.2.3
    # - Hyphen ranges: 1.2.3 - 4.5.6
    # - Comma-separated: 1.2, 2
    # - Exact versions: 1.2.3
    try
        version_spec = Pkg.Types.semver_spec(constraint)
        return constraint  # Return original constraint if semver_spec can parse it
    catch e
        # If semver_spec fails, try some fallback handling

        # Handle exact match with equals
        if startswith(constraint, "=")
            version_part = constraint[2:end]
            try
                Pkg.Types.VersionNumber(version_part)  # Validate it's a valid version
                return version_part  # Return just the version part
            catch
                return constraint
            end
        end

        # For any other invalid format, return as-is and let caller handle the error
        return constraint
    end
end

"""
    parse_julia_version_constraint(constraint::String)

Parse a Julia version constraint string into a structured format using the official
Pkg.jl semver_spec function.

Supports all official Julia version constraint formats:
- Caret constraints: ^1.2.3 (compatible upgrades, follows semver)
- Tilde constraints: ~1.2.3 (patch-level changes only)
- Inequality constraints: >=1.2.3, <2.0.0
- Hyphen ranges: 1.2.3 - 4.5.6
- Comma-separated: 1.2, 2
- Exact versions: 1.2.3
- Wildcard: * (any version)

Returns a Dict with keys:
- "type": "parsed", "wildcard", or "error"
- "constraint": original constraint string (for parsed)
- "version_spec": "*" (for wildcard)
- "error": error message (for error)
"""
function parse_julia_version_constraint(constraint::String)
    try
        # Handle wildcard constraints (semver_spec doesn't support these)
        if isempty(constraint) || constraint == "*"
            return Dict(
                "type" => "wildcard",
                "version_spec" => "*"
            )
        end

        # Use Julia's semver_spec to parse the constraint
        # This handles ^, ~, >=, <, hyphen ranges, comma-separated, etc.
        version_spec = Pkg.Types.semver_spec(constraint)

        return Dict(
            "type" => "parsed",
            "constraint" => constraint
        )
    catch e
        return Dict(
            "type" => "error",
            "error" => sprint(showerror, e)
        )
    end
end

"""
    check_version_satisfies_constraint(version::String, constraint::String)

Check if a version satisfies a given constraint using Julia's official semver_spec.

Uses the same constraint parsing logic as Julia's Pkg manager, ensuring compatibility
with all standard version constraint formats used in Project.toml [compat] sections.

Args:
- version: Version string to test (e.g., "1.2.3")
- constraint: Constraint string (e.g., "^1.0", "~1.2.3", ">=1.0", etc.)

Returns:
- Boolean: true if version satisfies constraint, false otherwise

Special handling:
- "*" constraint always returns true
- Invalid versions or constraints return false
"""
function check_version_satisfies_constraint(version::String, constraint::String)
    try
        # Parse the version
        parsed_version = Pkg.Types.VersionNumber(version)

        # Handle wildcard constraint
        if constraint == "*"
            return true
        end

        # Use Julia's semver_spec to parse the constraint
        version_spec = Pkg.Types.semver_spec(constraint)

        # Check if version satisfies constraint
        satisfies = parsed_version in version_spec

        return satisfies
    catch e
        return false
    end
end

"""
    expand_version_constraint(constraint::String)

Expand a version constraint to show example versions that would match.

Uses Julia's official semver_spec to parse the constraint, then generates
example version numbers that satisfy the constraint. This helps understand
what versions would be considered compatible.

Returns a Dict with keys:
- "type": "constraint", "wildcard", or "error"
- "original": original constraint string
- "ranges": array of example version strings that match
- "description": human-readable description (for wildcard)
- "error": error message (for error)

Note: This generates example versions for demonstration purposes.
In practice, you would query actual available package versions.
"""
function expand_version_constraint(constraint::String)
    try
        # Handle wildcard constraints
        if isempty(constraint) || constraint == "*"
            return Dict(
                "type" => "wildcard",
                "description" => "Matches any version"
            )
        end

        # Use Julia's semver_spec to parse the constraint
        version_spec = Pkg.Types.semver_spec(constraint)

        # Generate some example versions that would match
        examples = []

        # This is a simplified expansion - in practice, you'd query available versions
        for major in 0:5
            for minor in 0:9
                for patch in 0:9
                    test_version = Pkg.Types.VersionNumber("$major.$minor.$patch")
                    if test_version in version_spec && length(examples) < 10
                        push!(examples, string(test_version))
                    end
                end
            end
        end

        return Dict(
            "type" => "constraint",
            "original" => constraint,
            "ranges" => examples
        )
    catch e
        return Dict(
            "type" => "error",
            "error" => sprint(showerror, e)
        )
    end
end

# ============================================================================
# PACKAGE DISCOVERY AND METADATA
# ============================================================================

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
    catch e
        return Dict("error" => "Failed to get latest version: $(sprint(showerror, e))")
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
    catch e
        return Dict("error" => "Failed to get package metadata: $(sprint(showerror, e))")
    end
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
    catch e
        return Dict("error" => "Failed to fetch package versions: $(sprint(showerror, e))")
    end
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
    catch e
        return Dict("error" => "Failed to fetch package info: $(sprint(showerror, e))")
    end
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
    catch e
        return Dict("error" => "Failed to find source URL: $(sprint(showerror, e))")
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
    catch e
        return Dict("error" => "Registry lookup failed: $(sprint(showerror, e))")
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
    catch e
        return Dict("error" => "Failed to extract metadata from URL: $(sprint(showerror, e))")
    end
end

# ============================================================================
# DEPENDENCY RESOLUTION AND COMPATIBILITY CHECKING
# ============================================================================

"""
    check_update_compatibility(project_path::String, package_name::String, target_version::String)

Check if updating a package to a target version is compatible with the project
"""
function check_update_compatibility(project_path::String, package_name::String, target_version::String)
    try
        # Create a temporary copy of the project for testing
        mktempdir() do temp_dir
            # Copy project files
            project_file = joinpath(project_path, "Project.toml")
            manifest_file = joinpath(project_path, "Manifest.toml")

            temp_project = joinpath(temp_dir, "Project.toml")
            temp_manifest = joinpath(temp_dir, "Manifest.toml")

            cp(project_file, temp_project)
            if isfile(manifest_file)
                cp(manifest_file, temp_manifest)
            end

            # Test the update
            Pkg.activate(temp_dir) do
                with_autoprecompilation_disabled() do
                    try
                        # Try to add the specific version
                        pkg_spec = Pkg.PackageSpec(name=package_name, version=target_version)
                        Pkg.add(pkg_spec; io=devnull)

                        # If we get here, the update is compatible
                        # Get the resolved versions
                        deps = Pkg.dependencies()
                        resolved_versions = Dict{String,String}()

                        for (uuid, dep) in deps
                            if !isnothing(dep.version)
                                resolved_versions[dep.name] = string(dep.version)
                            end
                        end

                        return Dict(
                            "compatible" => true,
                            "package_name" => package_name,
                            "target_version" => target_version,
                            "resolved_versions" => resolved_versions
                        )
                    catch e
                        return Dict(
                            "compatible" => false,
                            "package_name" => package_name,
                            "target_version" => target_version,
                            "error" => sprint(showerror, e)
                        )
                    end
                end
            end
        end
    catch e
        return Dict(
            "compatible" => false,
            "package_name" => package_name,
            "target_version" => target_version,
            "error" => "Compatibility check failed: $(sprint(showerror, e))"
        )
    end
end

"""
    resolve_dependencies_with_constraints(project_path::String, target_updates::Dict)

Resolve dependencies with multiple package updates and constraints
"""
function resolve_dependencies_with_constraints(project_path::String, target_updates::Dict)
    try
        # Create a temporary copy for resolution testing
        mktempdir() do temp_dir
            # Copy project files
            project_file = joinpath(project_path, "Project.toml")
            manifest_file = joinpath(project_path, "Manifest.toml")

            temp_project = joinpath(temp_dir, "Project.toml")
            temp_manifest = joinpath(temp_dir, "Manifest.toml")

            cp(project_file, temp_project)
            if isfile(manifest_file)
                cp(manifest_file, temp_manifest)
            end

            # Perform resolution
            Pkg.activate(temp_dir) do
                with_autoprecompilation_disabled() do
                    resolution_results = Dict{String,Any}()

                    # Apply all updates
                    pkg_specs = Pkg.PackageSpec[]
                    for (package_name, target_version) in target_updates
                        push!(pkg_specs, Pkg.PackageSpec(name=package_name, version=Pkg.Types.VersionNumber(target_version)))
                    end
                    try
                        Pkg.add(pkg_specs; io=devnull)
                        for (package_name, target_version) in target_updates
                            resolution_results[package_name] = Dict(
                                "requested" => target_version,
                                "status" => "added"
                            )
                        end
                    catch e
                        for (package_name, target_version) in target_updates
                            resolution_results[package_name] = Dict(
                                "requested" => target_version,
                                "status" => "failed",
                                "error" => sprint(showerror, e)
                            )
                        end
                    end

                    try

                        # Get final resolved versions
                        deps = Pkg.dependencies()
                        final_versions = Dict{String,String}()

                        for (uuid, dep) in deps
                            if !isnothing(dep.version)
                                final_versions[dep.name] = string(dep.version)

                                # Update resolution results with actual versions
                                if haskey(resolution_results, dep.name)
                                    resolution_results[dep.name]["resolved"] = string(dep.version)
                                end
                            end
                        end

                        return Dict(
                            "success" => true,
                            "target_updates" => target_updates,
                            "resolution_results" => resolution_results,
                            "final_versions" => final_versions
                        )
                    catch e
                        return Dict(
                            "success" => false,
                            "target_updates" => target_updates,
                            "resolution_results" => resolution_results,
                            "resolution_error" => sprint(showerror, e)
                        )
                    end
                end
            end
        end
    catch e
        return Dict(
            "success" => false,
            "target_updates" => target_updates,
            "error" => "Resolution failed: $(sprint(showerror, e))"
        )
    end
end

# ============================================================================
# LEGACY REGISTRY OPERATIONS (For Backward Compatibility)
# ============================================================================

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

# Args wrapper for get_package_metadata function with optional UUID
function get_package_metadata(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return get_package_metadata(package_name, package_uuid)
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

# Args wrapper for fetch_package_info function with UUID requirement
function fetch_package_info(args::Dict)
    package_name = get(args, "package_name", "")
    package_uuid = get(args, "package_uuid", "")

    if isempty(package_name) || isempty(package_uuid)
        return Dict("error" => "Both package_name and package_uuid are required")
    end

    return fetch_package_info(package_name, package_uuid)
end
