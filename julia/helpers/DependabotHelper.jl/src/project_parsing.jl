# Project and manifest parsing functions for DependabotHelper.jl
#
# NOTE: Terminology clarification for Julia vs Dependabot:
# - This module uses Julia terminology: "project file" = Project.toml, "manifest file" = Manifest.toml
# - Dependabot terminology: "manifest file" = Project.toml, "lockfile" = Manifest.toml
# - Function names and documentation use Julia terminology for consistency with the ecosystem

"""
    parse_project(project_path::String, manifest_path::Union{String,Nothing}=nothing)

Parse a Julia project file (Project.toml) and return comprehensive project information.

Note: In Dependabot terminology, this would be called parsing a "manifest file" or "dependency manifest".
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
        end
    catch ex
        @error "parse_project: Failed to parse project" exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to parse project: $(sprint(showerror, ex))")
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
                        push!(pkg_specs, Pkg.PackageSpec(name=package_name, version=target_version))
                    end
                    try
                        # Try to add/update the packages with the specific versions
                        Pkg.add(pkg_specs)
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
    catch ex
        @error "update_manifest: Failed to update manifest" exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to update manifest: $(sprint(showerror, ex))")
    end
end

"""
    update_manifest(args::Dict)

Args wrapper for update_manifest function
"""
function update_manifest(args::Dict)
    return update_manifest(args["project_path"], args["updates"])
end
