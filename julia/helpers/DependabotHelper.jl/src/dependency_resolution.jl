# Dependency resolution and compatibility checking functions for DependabotHelper.jl

"""
    check_update_compatibility(project_path::String, package_name::String, target_version::String)

Check if updating a package to a target version is compatible with the project
"""
function check_update_compatibility(project_path::String, package_name::String, target_version::String)
    # Validate inputs first
    project_file = joinpath(project_path, "Project.toml")
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
            # Copy project files
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
    # Validate inputs first
    project_file = joinpath(project_path, "Project.toml")
    if !isfile(project_file)
        return Dict(
            "success" => false,
            "target_updates" => target_updates,
            "error" => "Project.toml not found at: $project_file"
        )
    end

    try
        # Create a temporary copy for resolution testing
        mktempdir() do temp_dir
            # Copy project files
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
                        Pkg.add(pkg_specs)
                        for (package_name, target_version) in target_updates
                            resolution_results[package_name] = Dict(
                                "requested" => target_version,
                                "status" => "added"
                            )
                        end
                    catch e
                        @error "Failed to add package specifications during dependency resolution" pkg_specs exception=(e, catch_backtrace())
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
