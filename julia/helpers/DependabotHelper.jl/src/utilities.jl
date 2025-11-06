# Core utility functions for DependabotHelper.jl

"""
    with_autoprecompilation_disabled(f::Function)

Helper function to disable precompilation during Pkg operations
"""
function with_autoprecompilation_disabled(f::Function)
    withenv("JULIA_PKG_PRECOMPILE_AUTO" => "0") do
        return f()
    end
end

"""
    find_environment_files(dir::String)

Find the active project and manifest files in a directory using Julia's Pkg.
Returns a tuple (project_file, manifest_file) with the actual file paths.

Julia supports multiple naming conventions:
- Project files: Project.toml or JuliaProject.toml
- Manifest files: Manifest.toml or JuliaManifest.toml (with optional version suffix)

This function uses Pkg.Types.Context to detect which files are actually being used,
including support for Julia workspaces where the manifest may be located in a parent
directory specified by the [workspace] section in Project.toml.
"""
function find_environment_files(dir::String)
    if !isdir(dir)
        error("Directory does not exist: $dir")
    end

    # Use Pkg to find the actual environment files
    Pkg.activate(dir) do
        ctx = Pkg.Types.Context()
        project_file = ctx.env.project_file
        manifest_file = ctx.env.manifest_file
        return (project_file, manifest_file)
    end
end

"""
    get_project_file_name(dir::String)

Get the name of the project file in a directory (e.g., "Project.toml" or "JuliaProject.toml").
"""
function get_project_file_name(dir::String)
    project_file, _ = find_environment_files(dir)
    return basename(project_file)
end

"""
    get_manifest_file_name(dir::String)

Get the name of the manifest file in a directory (e.g., "Manifest.toml" or "JuliaManifest.toml").
"""
function get_manifest_file_name(dir::String)
    _, manifest_file = find_environment_files(dir)
    return basename(manifest_file)
end

"""
    detect_workspace_files(dir::String)

Detect if the given directory contains a workspace and return all relevant files.
Returns a dictionary with:
- "is_workspace": Boolean indicating if this is a workspace root or member
- "project_files": Array of absolute paths to all Project.toml files (workspace members + root if workspace)
- "manifest_file": String path to the shared Manifest.toml

If not a workspace, returns the single project and manifest for the directory.
"""
function detect_workspace_files(dir::String)
    if !isdir(dir)
        error("Directory does not exist: $dir")
    end

    project_file, manifest_file = find_environment_files(dir)

    # Check if current project is a workspace root
    project_data = TOML.parsefile(project_file)
    is_workspace_root = haskey(project_data, "workspace") && haskey(project_data["workspace"], "projects")

    # Use Base.base_project to find the workspace root (if we're a member)
    base_project_file = Base.base_project(project_file)

    if is_workspace_root || base_project_file !== nothing
        # This is a workspace - either root or member
        # Use the base project file (or current if we're the root)
        workspace_root = base_project_file !== nothing ? base_project_file : project_file
        workspace_data = TOML.parsefile(workspace_root)

        if haskey(workspace_data, "workspace") && haskey(workspace_data["workspace"], "projects")
            workspace_members = workspace_data["workspace"]["projects"]
            project_files = String[]

            # Add the root project file
            push!(project_files, workspace_root)

            # Add all member project files
            base_dir = dirname(workspace_root)
            for member in workspace_members
                member_dir = joinpath(base_dir, member)
                if isdir(member_dir)
                    member_project_file, _ = find_environment_files(member_dir)
                    push!(project_files, member_project_file)
                end
            end

            # Get the shared manifest - use workspace_manifest or fall back to manifest_file
            workspace_manifest_file = Base.workspace_manifest(project_file)
            if workspace_manifest_file === nothing
                # If we're at the root, workspace_manifest returns nothing, so use the direct manifest
                workspace_manifest_file = manifest_file
            end

            return Dict(
                "is_workspace" => true,
                "project_files" => project_files,
                "manifest_file" => workspace_manifest_file
            )
        end
    end

    # Not a workspace member, return single project
    return Dict(
        "is_workspace" => false,
        "project_files" => [project_file],
        "manifest_file" => manifest_file
    )
end
