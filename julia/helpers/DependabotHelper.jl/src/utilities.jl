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
    find_workspace_project_files(dir::String)

Find all Project.toml files in a workspace that share the same manifest file.
Returns a Dict with:
- "project_files": Array of absolute paths to all Project.toml files in the workspace
- "manifest_file": Absolute path to the shared manifest file
- "workspace_root": Absolute path to the workspace root directory

This function discovers workspace member Project.toml files using Julia's native approach:
1. Finding the manifest file for the given directory (which points to the workspace root)
2. Reading the [workspace].projects array from the root Project.toml (authoritative source)
3. Recursively processing nested workspaces
"""
function find_workspace_project_files(dir::String)
    if !isdir(dir)
        return Dict("error" => "Directory does not exist: $dir")
    end

    try
        # First find the environment files for the given directory
        # Julia's Pkg.Types.Context handles workspace detection automatically
        project_file, manifest_file = find_environment_files(dir)

        if !isfile(manifest_file)
            # No manifest file found, just return the single project file
            return Dict(
                "project_files" => [project_file],
                "manifest_file" => "",
                "workspace_root" => dirname(project_file)
            )
        end

        # The workspace root is where the manifest file lives
        workspace_root = dirname(manifest_file)
        project_files = String[]

        # Use Julia's authoritative approach: read [workspace].projects from root Project.toml
        # This matches how Julia's base_project() function works in Base.loading
        collect_workspace_projects!(project_files, workspace_root)

        # Ensure the original project file is included (in case it's not in [workspace].projects)
        if isfile(project_file) && !(project_file in project_files)
            push!(project_files, project_file)
        end

        return Dict(
            "project_files" => project_files,
            "manifest_file" => manifest_file,
            "workspace_root" => workspace_root
        )
    catch ex
        @error "find_workspace_project_files: Failed to find workspace project files" exception=(ex, catch_backtrace())
        return Dict("error" => "Failed to find workspace project files: $(sprint(showerror, ex))")
    end
end

"""
    collect_workspace_projects!(project_files::Vector{String}, dir::String)

Recursively collect all Project.toml files in a workspace by reading the [workspace].projects
array from each Project.toml. This follows Julia's native workspace discovery pattern.
"""
function collect_workspace_projects!(project_files::Vector{String}, dir::String)
    # Find the project file in this directory
    proj_file = nothing
    for name in ("JuliaProject.toml", "Project.toml")
        candidate = joinpath(dir, name)
        if isfile(candidate)
            proj_file = candidate
            break
        end
    end

    proj_file === nothing && return

    # Add this project file if not already present
    if !(proj_file in project_files)
        push!(project_files, proj_file)
    end

    # Parse the project file to find workspace members
    try
        proj_data = Pkg.TOML.parsefile(proj_file)
        workspace = get(proj_data, "workspace", nothing)

        if workspace !== nothing
            # Get the projects array from [workspace] section
            workspace_projects = get(workspace, "projects", nothing)

            if workspace_projects isa Vector
                for member_path in workspace_projects
                    member_dir = joinpath(dir, member_path)
                    if isdir(member_dir)
                        # Recursively collect projects from this member (handles nested workspaces)
                        collect_workspace_projects!(project_files, member_dir)
                    end
                end
            elseif workspace_projects isa String
                # Single project specified as string
                member_dir = joinpath(dir, workspace_projects)
                if isdir(member_dir)
                    collect_workspace_projects!(project_files, member_dir)
                end
            end
        end
    catch ex
        @warn "Failed to parse project file for workspace members" proj_file exception=(ex, catch_backtrace())
    end
end

"""
    find_workspace_project_files(args::AbstractDict)

Args wrapper for find_workspace_project_files function.
"""
function find_workspace_project_files(args::AbstractDict)
    directory = get(args, "directory", "")
    if isempty(directory)
        return Dict("error" => "directory argument is required")
    end
    return find_workspace_project_files(directory)
end
