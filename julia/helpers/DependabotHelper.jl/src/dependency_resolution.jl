# Dependency resolution and compatibility checking functions for DependabotHelper.jl

"""
    check_update_compatibility(project_path::String, package_name::String, target_version::String, package_uuid::String)

Check if updating a package to a target version is compatible with the project.
Requires UUID to uniquely identify the package and avoid name collisions across registries.
"""
function check_update_compatibility(project_path::String, package_name::String, target_version::String, package_uuid::String)
    # Validate inputs first - find the actual environment files
    project_file, manifest_file = try
        find_environment_files(project_path)
    catch e
        return Dict(
            "compatible" => false,
            "package_name" => package_name,
            "target_version" => target_version,
            "error" => "Failed to find environment files: $(sprint(showerror, e))"
        )
    end

    if !isfile(project_file)
        return Dict(
            "compatible" => false,
            "package_name" => package_name,
            "target_version" => target_version,
            "error" => "Project file not found at: $project_file"
        )
    end

    try
        # Create a temporary copy of the project for testing
        mktempdir() do temp_dir
            # Preserve the relative path relationship between project and manifest
            project_rel = relpath(project_file, dirname(manifest_file))

            temp_project = joinpath(temp_dir, project_rel)
            temp_manifest = joinpath(temp_dir, basename(manifest_file))

            # Create any necessary parent directories for the project file
            mkpath(dirname(temp_project))

            cp(project_file, temp_project)
            if isfile(manifest_file)
                cp(manifest_file, temp_manifest)
            end

            # Test the update
            Pkg.activate(dirname(temp_project)) do
                with_autoprecompilation_disabled() do
                    try
                        # Create PackageSpec with UUID for unambiguous package identification
                        uuid_obj = Base.UUID(package_uuid)
                        pkg_spec = Pkg.PackageSpec(name=package_name, uuid=uuid_obj, version=target_version)
                        Pkg.add(pkg_spec)

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
                        @error "Compatibility check failed for package update" package_name target_version exception=(e, catch_backtrace())
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
        @error "Compatibility check failed" project_path package_name target_version exception=(e, catch_backtrace())
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
    # Validate inputs first - find the actual environment files
    project_file, manifest_file = try
        find_environment_files(project_path)
    catch e
        return Dict(
            "success" => false,
            "target_updates" => target_updates,
            "error" => "Failed to find environment files: $(sprint(showerror, e))"
        )
    end

    if !isfile(project_file)
        return Dict(
            "success" => false,
            "target_updates" => target_updates,
            "error" => "Project file not found at: $project_file"
        )
    end

    try
        # Create a temporary copy for resolution testing
        mktempdir() do temp_dir
            # Preserve the relative path relationship between project and manifest
            project_rel = relpath(project_file, dirname(manifest_file))

            temp_project = joinpath(temp_dir, project_rel)
            temp_manifest = joinpath(temp_dir, basename(manifest_file))

            # Create any necessary parent directories for the project file
            mkpath(dirname(temp_project))

            cp(project_file, temp_project)
            if isfile(manifest_file)
                cp(manifest_file, temp_manifest)
            end

            # Perform resolution
            Pkg.activate(dirname(temp_project)) do
                with_autoprecompilation_disabled() do
                    resolution_results = Dict{String,Any}()

                    # Apply all updates - updates is keyed by UUID
                    pkg_specs = Pkg.PackageSpec[]
                    for (uuid_str, update_info) in target_updates
                        package_name = update_info["name"]
                        target_version = update_info["version"]
                        uuid_obj = Base.UUID(uuid_str)

                        push!(pkg_specs, Pkg.PackageSpec(name=package_name, uuid=uuid_obj, version=Pkg.Types.VersionNumber(target_version)))
                    end
                    try
                        Pkg.add(pkg_specs)
                        for (uuid_str, update_info) in target_updates
                            package_name = update_info["name"]
                            target_version = update_info["version"]
                            resolution_results[package_name] = Dict(
                                "requested" => target_version,
                                "status" => "added"
                            )
                        end
                    catch e
                        @error "Failed to add package specifications during dependency resolution" pkg_specs exception=(e, catch_backtrace())
                        for (uuid_str, update_info) in target_updates
                            package_name = update_info["name"]
                            target_version = update_info["version"]
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
                        @error "Failed to get final resolved versions after dependency resolution" exception=(e, catch_backtrace())
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
        @error "Dependency resolution with constraints failed" project_path target_updates exception=(e, catch_backtrace())
        return Dict(
            "success" => false,
            "target_updates" => target_updates,
            "error" => "Resolution failed: $(sprint(showerror, e))"
        )
    end
end
