# Environments written by past Julia releases, kept in `julia_version.toml` next to this
# file. Each release set up the environment below: registry packages (one pinned, one with
# extensions), a dependency also listed in [weakdeps], a stdlib with an extension (Pkg,
# from 1.11), an upgradable stdlib, a developed path, a [sources] path dependency (from
# 1.11) and a package added from git at a commit. `project` and `manifest` record the
# result, and `expected` the manifest after adding JSON 0.21.4 following the compat edit
# in `update_project!`.
#
# To add releases, pass their Julia executables:
#
#     julia julia_version.jl /path/to/julia-1.14.0/bin/julia

using TOML

const MANIFESTS_FILE = joinpath(@__DIR__, "julia_version.toml")

manifests() = TOML.parsefile(MANIFESTS_FILE)

const LOCAL_PACKAGES = Dict(
    "LocalPkg" => "5e1b3a5c-5d0c-4c5e-9b8a-1f2d3c4b5a69",
    "DevPkg" => "0f4d1e9a-3c7b-4a52-8e6d-2b9f5a1c7d30",
)

function project_toml(julia_version::VersionNumber)
    deps = [
        "JSON = \"682c06a0-de6a-54ab-a142-c8b1cf79cde6\"",
        "LinearAlgebra = \"37e2e46d-f89d-539d-b4ee-838fcccc9c8e\"",
        "Pkg = \"44cfe95a-1eb2-52ea-b672-e2afdf69b78f\"",
    ]
    sources = julia_version >= v"1.11"
    sources && push!(deps, "LocalPkg = \"$(LOCAL_PACKAGES["LocalPkg"])\"")
    return """
    [deps]
    $(join(sort(deps), "\n"))

    [weakdeps]
    LinearAlgebra = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"
    $(sources ? "\n[sources]\nLocalPkg = {path = \"LocalPkg\"}\n" : "")
    [compat]
    JSON = "0.21.3 - 0.21"
    LinearAlgebra = "1"
    julia = "1.10"
    """
end

# The steps a release runs in the environment after the project above is written
const SETUP_SCRIPT = """
import Pkg
Pkg.activate(".")
Pkg.develop(path = "DevPkg")
Pkg.add(url = "https://github.com/JuliaLang/Example.jl", rev = "f703bdd8c4ccb13da46fc7bf5be7bd6119b5aa10")
Pkg.add([
    Pkg.PackageSpec(name = "JSON", version = v"0.21.3"),
    Pkg.PackageSpec(name = "Parsers", version = v"2.8.1"),
    Pkg.PackageSpec(name = "Compat", version = v"4.18.1"),
    Pkg.PackageSpec(name = "Statistics"),
])
Pkg.pin("Parsers")
"""

const UPDATE_SCRIPT = """
import Pkg
Pkg.activate(".")
Pkg.add(Pkg.PackageSpec(name = "JSON", version = v"0.21.4"))
"""

# A new environment with the local packages, and the project and manifest if given
function environment(project::String, manifest::Union{Nothing, String} = nothing)
    dir = mktempdir()
    for (name, uuid) in LOCAL_PACKAGES
        mkpath(joinpath(dir, name, "src"))
        write(joinpath(dir, name, "Project.toml"), "name = \"$name\"\nuuid = \"$uuid\"\nversion = \"0.1.0\"\n")
        write(joinpath(dir, name, "src", "$name.jl"), "module $name end\n")
    end
    write(joinpath(dir, "Project.toml"), project)
    manifest === nothing || write(joinpath(dir, "Manifest.toml"), manifest)
    return dir
end

function update_project!(dir::String)
    project_file = joinpath(dir, "Project.toml")
    return write(project_file, replace(read(project_file, String), "\"0.21.3 - 0.21\"" => "\"0.21.4 - 0.21\""))
end

function run_script(julia::String, dir::String, script::String)
    cmd = Cmd(`$julia --startup-file=no --history-file=no -e $script`; dir)
    return run(addenv(cmd, "JULIA_PKG_PRECOMPILE_AUTO" => "0"))
end

function generate(julias::Vector{String})
    all = isfile(MANIFESTS_FILE) ? manifests() : Dict{String, Any}()
    for julia in julias
        julia_version = VersionNumber(readchomp(`$julia --startup-file=no -e 'print(VERSION)'`))
        dir = environment(project_toml(julia_version))
        run_script(julia, dir, SETUP_SCRIPT)
        written = Dict(
            "project" => read(joinpath(dir, "Project.toml"), String),
            "manifest" => read(joinpath(dir, "Manifest.toml"), String),
        )
        update_project!(dir)
        run_script(julia, dir, UPDATE_SCRIPT)
        written["expected"] = read(joinpath(dir, "Manifest.toml"), String)
        all[string(julia_version)] = written
    end
    # Literal strings keep the files readable and their diffs small
    return open(MANIFESTS_FILE, "w") do io
        println(io, "# Written by julia_version.jl")
        for key in sort!(collect(keys(all)); by = VersionNumber)
            print(io, "\n[\"", key, "\"]\n")
            for field in ("project", "manifest", "expected")
                text = all[key][field]
                @assert !occursin("'''", text)
                print(io, field, " = '''\n", text, "'''\n")
            end
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    generate(ARGS)
end
