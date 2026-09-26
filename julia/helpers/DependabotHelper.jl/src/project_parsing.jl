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

            # Extract basic information. Non-package environments (a plain
            # [deps]/[compat] Project.toml) have no name/version/uuid; emit
            # JSON null rather than the literal string "nothing".
            name = project_info.name
            version = project_info.version === nothing ? nothing : string(project_info.version)
            uuid = project_info.uuid === nothing ? nothing : string(project_info.uuid)

            # Note: Following CompatHelper.jl's approach, we don't use Manifest.toml
            # for version information. Dependabot should update based on [compat]
            # constraints in Project.toml, not locked versions in Manifest.toml.

            # Packages pinned to a path or git source via [sources] (Julia 1.11+)
            # are not registry-updatable; Dependabot must not propose version
            # updates for them.
            sources = project_info.sources

            # Packages that ship with any Julia release the project supports
            # must not have their compat entries track registry releases; they
            # get the versions the project has to accept instead. An
            # environment is bounded by the julia compat of the projects it
            # resolves with too, so those must be laid out on disk around it.
            julia_compat = effective_julia_compat(ctx.env)
            stdlib_julia_versions = julia_versions_for_compat(julia_compat)
            function add_stdlib_info!(dep_info, dep_uuid)
                dep_info["stdlib"] = is_stdlib_for_julia_versions(dep_uuid, stdlib_julia_versions)
                if dep_info["stdlib"]
                    dep_info["stdlib_versions"] = [string(v) for v in stdlib_versions_for_julia_compat(dep_uuid, julia_compat)]
                end
                return dep_info
            end

            # The [compat] entry for a package as written in the project file
            function compat_string(dep_name)
                compat_spec = project_info.compat[dep_name]
                return isa(compat_spec, Pkg.Types.Compat) ? compat_spec.str : string(compat_spec)
            end

            # A [deps], [weakdeps] or [extras] section as dependency records
            function section_dependencies(section)
                deps = []
                for (dep_name, dep_uuid) in section
                    haskey(sources, dep_name) && continue

                    dep_info = Dict{String,Any}(
                        "name" => dep_name,
                        "uuid" => string(dep_uuid)
                    )
                    add_stdlib_info!(dep_info, dep_uuid)
                    # No compat entry means any version is acceptable in Julia,
                    # so no requirement field is emitted
                    if haskey(project_info.compat, dep_name)
                        dep_info["requirement"] = compat_string(dep_name)
                    end
                    push!(deps, dep_info)
                end
                return deps
            end

            dependencies = section_dependencies(project_info.deps)
            weak_dependencies = section_dependencies(project_info.weakdeps)
            # Pkg allows a package under [extras] as well as [deps] or
            # [weakdeps] (the documented way to test an extension); that
            # section already covers it
            extras = filter(project_info.extras) do (dep_name, _)
                !haskey(project_info.deps, dep_name) && !haskey(project_info.weakdeps, dep_name)
            end
            extra_dependencies = section_dependencies(extras)

            julia_version = haskey(project_info.compat, "julia") ? compat_string("julia") : ""

            return Dict{String,Any}(
                "name" => name,
                "version" => version,
                "uuid" => uuid,
                "julia_version" => julia_version,
                "dependencies" => dependencies,
                "weak_dependencies" => weak_dependencies,
                "extra_dependencies" => extra_dependencies,
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
    update_manifest(project_path::String, updates::Dict, manifest_file=nothing)

Update the manifest with new package versions.
`manifest_file` picks one of the environment's manifests, such as a
version-specific `Manifest-v1.12.toml`; by default it is the one the running Julia uses.
"""
function update_manifest(project_path::String, updates::Dict, manifest_file::Union{String,Nothing}=nothing)
    try
        # Validate inputs
        if !isdir(project_path)
            return Dict("error" => "Project directory does not exist")
        end

        # Find the actual environment files (handles JuliaProject.toml, etc.)
        project_file, default_manifest_file = find_environment_files(project_path)
        manifest_file = something(manifest_file, default_manifest_file)

        if !isfile(project_file)
            return Dict("error" => "Project file not found in directory")
        end

        if !isfile(manifest_file)
            return Dict("error" => "Manifest file not found in directory")
        end

        # NOTE: This function expects the project file to already have updated [compat]
        # constraints. The Ruby FileUpdater should update the project file first, then call
        # this function to update the manifest file based on the new constraints.

        # Pkg.add promotes packages into [deps], so it must only ever see
        # packages that are already direct dependencies of this project.
        # Updates for weakdeps (or [sources]-pinned packages) only change
        # Project.toml; the manifest doesn't lock them for the root project.
        project_toml = TOML.parsefile(project_file)
        direct_deps = get(project_toml, "deps", Dict{String,Any}())
        sources = get(project_toml, "sources", Dict{String,Any}())

        pkg_specs = Pkg.PackageSpec[]
        for (uuid_str, update_info) in updates
            package_name = update_info["name"]
            target_version = update_info["version"]

            if get(direct_deps, package_name, nothing) != uuid_str || haskey(sources, package_name)
                @info "update_manifest: skipping $(package_name) (not a registry-sourced direct dependency)"
                continue
            end

            push!(pkg_specs, Pkg.PackageSpec(name=package_name, uuid=Base.UUID(uuid_str), version=target_version))
        end

        isempty(pkg_specs) || add_packages(project_path, manifest_file, pkg_specs)

        updated_manifest_content = read(manifest_file, String)
        # Pkg only reads a manifest by the name it expects, which a version-specific
        # manifest may not have in the running Julia, so parse a copy.
        updated_manifest = mktempdir() do dir
            path = joinpath(dir, "Manifest.toml")
            write(path, updated_manifest_content)
            parse_manifest(path)
        end
        if haskey(updated_manifest, "error")
            return updated_manifest
        end

        # Calculate the relative path from project to manifest for Ruby
        # This handles workspace cases where manifest might be ../Manifest.toml
        # Real paths, since the caller's manifest path and Pkg's project path may
        # reach the same directory through different symlinks
        manifest_relative_path = relpath(realpath(manifest_file), dirname(realpath(project_file)))

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
    add_packages(project_path, manifest_file, pkg_specs)

`Pkg.add` the packages to the project, under the Julia version that wrote the manifest.

A resolve under another Julia version rewrites `julia_version` and the stdlib entries,
leaving a manifest the project's own Julia may not load. When the manifest names a
different version, juliaup installs and launches it. Without juliaup, or when it
cannot provide that version, the packages are added with the running Julia.
"""
function add_packages(project_path::String, manifest_file::String, pkg_specs::Vector{Pkg.PackageSpec})
    julia_version = manifest_julia_version(manifest_file)
    launcher = julia_version === nothing ? nothing : juliaup_launcher(julia_version)
    if launcher === nothing
        _, used_manifest_file = find_environment_files(project_path)
        if !(isfile(used_manifest_file) && samefile(used_manifest_file, manifest_file))
            error("Julia $VERSION does not use $(basename(manifest_file)), and no Julia that does could be launched")
        end
        Pkg.activate(project_path) do
            with_autoprecompilation_disabled() do
                Pkg.add(pkg_specs)
            end
        end
    else
        add_packages_with(launcher, julia_version, project_path, manifest_file, pkg_specs)
    end
end

"""
    manifest_julia_version(manifest_file) -> Union{VersionNumber,Nothing}

The `julia_version` recorded in the manifest, or `nothing` when it is missing or
matches the running Julia.
"""
function manifest_julia_version(manifest_file::String)
    raw = get(TOML.parsefile(manifest_file), "julia_version", nothing)
    raw isa String || return nothing
    julia_version = tryparse(VersionNumber, raw)
    julia_version === nothing && return nothing
    running = VersionNumber(VERSION.major, VERSION.minor, VERSION.patch, VERSION.prerelease)
    return julia_version == running ? nothing : julia_version
end

"""
    juliaup_launcher(julia_version) -> Union{String,Nothing}

The path of juliaup's `julia` launcher after installing `julia_version` with juliaup,
or `nothing` when that is not possible.
"""
function juliaup_launcher(julia_version::VersionNumber)
    # Pkg writes prerelease builds' versions (e.g. `1.14.0-DEV.123`), which juliaup
    # can only map to a nightly channel, not the build that wrote the manifest.
    if !isempty(julia_version.prerelease)
        @warn "update_manifest: the manifest was written by prerelease Julia $julia_version; resolving with Julia $VERSION"
        return nothing
    end
    juliaup = Sys.which("juliaup")
    if juliaup === nothing
        @warn "update_manifest: juliaup is not available to launch Julia $julia_version; resolving with Julia $VERSION"
        return nothing
    end
    # Use the launcher installed beside juliaup, since the `julia` on PATH may not be it.
    launcher = joinpath(dirname(juliaup), Sys.iswindows() ? "julia.exe" : "julia")
    # Output goes to stderr because stdout carries the helper's JSON result.
    if !isfile(launcher) || !success(pipeline(`$juliaup add $julia_version`; stdout=stderr, stderr=stderr))
        @warn "update_manifest: juliaup cannot install Julia $julia_version; resolving with Julia $VERSION"
        return nothing
    end
    return launcher
end

# Runs in the manifest's Julia, which may be much older than the helper's, so it
# only uses Pkg APIs that have been stable since Julia 1.0.
const ADD_PACKAGES_SCRIPT = """
import Pkg
specs = [Pkg.PackageSpec(name=ARGS[i], uuid=Base.UUID(ARGS[i + 1]), version=ARGS[i + 2]) for i in 3:3:length(ARGS)]
try
    Pkg.activate(ARGS[1])
    used = Pkg.Types.Context().env.manifest_file
    if !(isfile(used) && samefile(used, ARGS[2]))
        print("Julia \$VERSION uses \$(basename(used)), not \$(basename(ARGS[2]))")
        exit(1)
    end
    Pkg.add(specs)
catch ex
    print(sprint(showerror, ex))
    exit(nameof(typeof(ex)) == :ResolverError ? 2 : 1)
end
"""

function add_packages_with(launcher::String, julia_version::VersionNumber, project_path::String, manifest_file::String, pkg_specs::Vector{Pkg.PackageSpec})
    spec_args = String[]
    for spec in pkg_specs
        push!(spec_args, spec.name, string(spec.uuid), string(spec.version))
    end
    cmd = `$launcher +$julia_version --startup-file=no --history-file=no -e $ADD_PACKAGES_SCRIPT $project_path $manifest_file $spec_args`
    cmd = addenv(cmd, "JULIA_PKG_PRECOMPILE_AUTO" => "0")

    @info "update_manifest: resolving with Julia $julia_version, the version that wrote the manifest"
    output = IOBuffer()
    proc = Base.run(pipeline(ignorestatus(cmd); stdout=output, stderr=stderr))
    success(proc) && return
    message = String(take!(output))
    isempty(message) && (message = "Julia $julia_version exited with code $(proc.exitcode)")
    proc.exitcode == 2 && throw(Pkg.Resolve.ResolverError(message))
    error("Julia $julia_version could not update the manifest: $message")
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

    manifest_path = get(args, "manifest_path", nothing)
    manifest_file = manifest_path === nothing ? nothing : abspath(project_path, string(manifest_path))
    return update_manifest(project_path, updates, manifest_file)
end
