# Project and manifest parsing functions for DependabotHelper.jl
#
# NOTE: Terminology clarification for Julia vs Dependabot:
# - This module uses Julia terminology: "project file" = Project.toml/JuliaProject.toml,
#   "manifest file" = Manifest.toml/JuliaManifest.toml
# - Dependabot terminology: "manifest file" = Project.toml, "lockfile" = Manifest.toml
# - Function names and documentation use Julia terminology for consistency with the ecosystem
#
# Julia supports multiple naming conventions for environment files:
# - Project files: Project.toml or JuliaProject.toml
# - Manifest files: Manifest.toml or JuliaManifest.toml (with optional version suffix like Manifest-v2.0.toml)
# This module uses find_environment_files() to detect the actual file names in use.

"""
    parse_project(project_path::String, manifest_path::Union{String,Nothing}=nothing)

Parse a Julia project file and return comprehensive project information.

Note: In Dependabot terminology, this would be called parsing a "manifest file" or "dependency manifest".
The function automatically detects whether the project uses Project.toml or JuliaProject.toml.
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

        # Use Pkg to load the project with proper environment management
        Pkg.activate(project_dir) do
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

            # Note: Following CompatHelper.jl's approach, we don't use Manifest.toml
            # for version information. Dependabot should update based on [compat]
            # constraints in Project.toml, not locked versions in Manifest.toml.

            # Parse Project.toml directly to get weakdeps (Julia's Pkg may not populate this field)
            project_toml = TOML.parsefile(project_path)

            # Get dependencies and add compat requirements
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
                        compat_spec.str
                    else
                        string(compat_spec)
                    end
                    dep_info["requirement"] = constraint_str
                end
                # Note: If no compat entry exists, we don't add a requirement field
                # Missing compat entry means any version is acceptable in Julia

                push!(dependencies, dep_info)
            end

            # Note: We don't process [extras] to match CompatHelper.jl behavior
            # CompatHelper only processes [deps] and [weakdeps]

            # Get weak dependencies (weakdeps) - available in Julia 1.9+
            # Read directly from TOML since Pkg may not populate project_info.weakdeps
            weak_dependencies = []
            if haskey(project_toml, "weakdeps")
                weakdeps_section = project_toml["weakdeps"]
                for (dep_name, dep_uuid_str) in weakdeps_section
                    weak_dep_info = Dict{String,Any}(
                        "name" => dep_name,
                        "uuid" => dep_uuid_str
                    )

                    # Add version constraint if available in compat
                    if haskey(project_info.compat, dep_name)
                        compat_spec = project_info.compat[dep_name]
                        # Extract the original constraint string
                        constraint_str = if isa(compat_spec, Pkg.Types.Compat)
                            compat_spec.str
                        else
                            string(compat_spec)
                        end
                        weak_dep_info["requirement"] = constraint_str
                    end
                    # Note: If no compat entry exists, we don't add a requirement field
                    # Missing compat entry means any version is acceptable in Julia

                    push!(weak_dependencies, weak_dep_info)
                end
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

            return Dict{String,Any}(
                "name" => name,
                "version" => version,
                "uuid" => uuid,
                "julia_version" => julia_version,
                "dependencies" => dependencies,
                "weak_dependencies" => weak_dependencies,
                "project_path" => ctx.env.project_file
            )
        end
    catch ex
        @error "parse_project: Failed to parse project" exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to parse project: $(sprint(showerror, ex))")
    end
end

"""
    parse_project(args::AbstractDict)

Args wrapper for parse_project function
"""
function parse_project(args::AbstractDict)
    return parse_project(args["project_path"], get(args, "manifest_path", nothing))
end

"""
    parse_manifest(manifest_path::String)

Parse a Julia manifest file (Manifest.toml) and return comprehensive dependency information.

Note: In Dependabot terminology, this would be called parsing a "lockfile".
Enhanced version with better error handling and comprehensive metadata.
"""
function parse_manifest(manifest_path::String)
    try
        if !isfile(manifest_path)
            return Dict("error" => "Manifest file not found: $manifest_path")
        end

        # Determine the project directory from manifest path
        project_dir = dirname(manifest_path)

        # Use Pkg to load the manifest with proper environment management
        Pkg.activate(project_dir) do
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
        end
    catch ex
        @error "parse_manifest: Failed to parse manifest" exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to parse manifest: $(sprint(showerror, ex))")
    end
end

"""
    parse_manifest(args::AbstractDict)

Args wrapper for parse_manifest function
"""
function parse_manifest(args::AbstractDict)
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
        for dep_info in dependencies
            if dep_info["name"] == name && (isempty(uuid) || dep_info["uuid"] == uuid)
                return Dict("version" => dep_info["version"])
            end
        end

        return Dict("error" => "Package $name not found in manifest")
    catch ex
        @error "get_version_from_manifest: Failed to get version from manifest" exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to get version from manifest: $(sprint(showerror, ex))")
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
        if !isdir(project_path)
            return Dict("error" => "Project directory does not exist")
        end

        # Find the actual environment files (handles JuliaProject.toml, etc.)
        project_file, manifest_file = find_environment_files(project_path)

        if !isfile(project_file)
            return Dict("error" => "Project file not found in directory")
        end

        if !isfile(manifest_file)
            return Dict("error" => "Manifest file not found in directory")
        end

        # NOTE: This function expects the project file to already have updated [compat]
        # constraints. The Ruby FileUpdater should update the project file first, then call
        # this function to update the manifest file based on the new constraints.

        # Activate the project directory and update directly
        Pkg.activate(project_path) do
            with_autoprecompilation_disabled() do
                # Process each update - updates is keyed by UUID
                pkg_specs = Pkg.PackageSpec[]
                for (uuid_str, update_info) in updates
                    package_name = update_info["name"]
                    target_version = update_info["version"]
                    uuid_obj = Base.UUID(uuid_str)

                    push!(pkg_specs, Pkg.PackageSpec(name=package_name, uuid=uuid_obj, version=target_version))
                end
                # Try to add/update the packages with the specific versions
                Pkg.add(pkg_specs)
            end
        end

        # After Pkg.add, find where the manifest actually is
        # For workspace packages, Pkg might have updated a different manifest location
        actual_project_file, actual_manifest_file = find_environment_files(project_path)

        # Read the updated manifest from the actual location
        if !isfile(actual_manifest_file)
            return Dict("error" => "Updated manifest file not found")
        end

        updated_manifest = parse_manifest(actual_manifest_file)
        if haskey(updated_manifest, "error")
            return updated_manifest
        end

        updated_manifest_content = read(actual_manifest_file, String)

        # Calculate the relative path from project to manifest for Ruby
        # This handles workspace cases where manifest might be ../Manifest.toml
        manifest_relative_path = relpath(actual_manifest_file, dirname(actual_project_file))

        return Dict(
            "result" => "success",
            "manifest_content" => updated_manifest_content,
            "manifest_path" => manifest_relative_path,
            "updated_manifest" => updated_manifest
        )
    catch ex
        @error "update_manifest: Failed to update manifest" exception=(ex, catch_backtrace())

        # Check if this is a Pkg resolver error - these indicate version conflicts
        error_prefix = if ex isa Pkg.Resolve.ResolverError
            "Pkg resolver error: "
        else
            "Failed to update manifest: "
        end

        return Dict("error" => error_prefix * sprint(showerror, ex))
    end
end

"""
    update_manifest(args::AbstractDict)

Args wrapper for update_manifest function
"""
function update_manifest(args::AbstractDict)
    project_path = string(get(args, "project_path", ""))
    updates_raw = get(args, "updates", Dict{String,Any}())

    # Convert JSON.Object or other AbstractDict to Dict{String,Any}
    # The updates dict is keyed by UUID, with values being dicts containing "name" and "version"
    updates = Dict{String,Any}()
    if updates_raw isa AbstractDict
        for (uuid_str, update_info) in updates_raw
            # Convert the nested dict as well (in case it's a JSON.Object)
            if update_info isa AbstractDict
                updates[string(uuid_str)] = Dict{String,Any}(
                    "name" => string(get(update_info, "name", "")),
                    "version" => string(get(update_info, "version", ""))
                )
            end
        end
    end

    if isempty(project_path) || isempty(updates)
        return Dict("error" => "Both project_path and updates are required")
    end

    return update_manifest(project_path, updates)
end
