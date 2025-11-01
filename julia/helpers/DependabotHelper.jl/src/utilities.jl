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
