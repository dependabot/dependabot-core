# Helper functions for working with Julia dependencies

"""
Parse a Project.toml file and return its dependencies
"""
function parse_project(args)
    project_path = args["project_path"]
    project = Pkg.TOML.parsefile(project_path)

    deps = Dict()
    if haskey(project, "deps")
        deps = project["deps"]
    end

    compat = Dict()
    if haskey(project, "compat")
        compat = project["compat"]
    end

    return Dict(
        "name" => get(project, "name", ""),
        "version" => get(project, "version", ""),
        "dependencies" => [
            Dict(
                "name" => name,
                "uuid" => uuid,
                "requirement" => get(compat, name, "*")
            ) for (name, uuid) in deps
        ]
    )
end

"""
Get the latest version of a package
"""
function get_latest_version(args)
    package_name = args["package_name"]
    current_version = args["current_version"]

    # Create a temporary environment to avoid modifying the global one
    temp_dir = mktempdir()
    original_project = Base.active_project()
    try
        # Initialize a project in the temporary directory
        Pkg.activate(temp_dir)

        # Add the package to get available versions
        Pkg.add(Pkg.PackageSpec(name=package_name))

        # Get installed package info
        pkg_info = Pkg.dependencies()[Pkg.Types.PackageId(package_name).uuid]

        return Dict(
            "version" => string(pkg_info.version)
        )
    finally
        Pkg.activate(original_project)  # Reset to previous environment
        rm(temp_dir, recursive=true, force=true)
    end
end

"""
Update a package in a Manifest.toml file
"""
function update_manifest(args)
    project_path = args["project_path"]
    manifest_path = args["manifest_path"]
    dependency_name = args["dependency_name"]
    dependency_version = get(args, "dependency_version", nothing)

    # Activate the project
    Pkg.activate(dirname(project_path))

    # Update the specific package to the target version
    if dependency_version !== nothing
        # Update to specific version if provided
        Pkg.add(Pkg.PackageSpec(name=dependency_name, version=dependency_version))
    else
        # Otherwise just update to latest version
        Pkg.update(dependency_name)
    end

    # Return success
    return Dict("updated" => true)
end
