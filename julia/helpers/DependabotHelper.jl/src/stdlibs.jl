# Standard library handling for DependabotHelper.jl
#
# Pkg pins a standard library to the version bundled with the running Julia,
# so a compat entry derived from a stdlib's registry releases (a legacy bridge
# such as Artifacts 1.3 for Julia 1.0-1.5, or an "upgradable" stdlib release
# such as Statistics 1.11) can make a project uninstallable on part of the
# Julia range its own `julia` compat entry admits. Pkg can say whether a
# package is a stdlib at a given `julia_version` (using the per-release data
# from HistoricalStdlibVersions.jl, as it does when resolving for another
# Julia), but a compat entry admits a range of releases and the stdlib set
# changes between them (Artifacts became a stdlib in 1.6, StyledStrings in
# 1.11), so the range is split into eras of constant stdlib set here and each
# era is checked with Pkg.

const JULIA_UUID = Base.UUID("1222c4b2-2114-5bfd-aeef-88e4692bbb3e")

# Before this release, Pkg.test() pinned stdlibs to v0.0.0 in the test
# sandbox, so a stdlib compat entry has to admit 0.0.0 as well. See
# https://discourse.julialang.org/t/psa-compat-requirements-in-the-general-registry-are-changing/104958
const STDLIB_TEST_SANDBOX_FIXED = v"1.10.0"

"""
    stdlib_eras(julia_compat) -> Vector{Tuple{VersionNumber, VersionSpec, Dict}}

Split the Julia releases admitted by `julia_compat` (a `VersionSpec`; `nothing`
admits every release) into eras with the same stdlib set. Each era is the
release the historical data records it from, the admitted releases within it,
and its stdlibs.
"""
function stdlib_eras(julia_compat::Union{Nothing, Pkg.Versions.VersionSpec})
    spec = something(julia_compat, Pkg.Versions.VersionSpec())
    eras = Tuple{VersionNumber, Pkg.Versions.VersionSpec, Dict{Base.UUID, Pkg.Types.StdlibInfo}}[]
    isempty(spec) && return eras

    isempty(Pkg.Types.STDLIBS_BY_VERSION) && HistoricalStdlibVersions.register!()
    by_version = Pkg.Types.STDLIBS_BY_VERSION
    # Each entry holds the stdlibs of that release and of every release before
    # the next entry
    for (i, (julia_version, stdlibs)) in enumerate(by_version)
        lower = Pkg.Versions.VersionBound(julia_version)
        upper = i < length(by_version) ? bound_below(first(by_version[i + 1])) : Pkg.Versions.VersionBound()
        admitted = intersect(spec, Pkg.Versions.VersionSpec(Pkg.Versions.VersionRange(lower, upper)))
        isempty(admitted) || push!(eras, (julia_version, admitted, stdlibs))
    end

    # Releases the historical data does not know about yet are assumed to ship
    # the running Julia's stdlibs
    from_current = Pkg.Versions.VersionSpec(Pkg.Versions.VersionRange(Pkg.Versions.VersionBound(VERSION), Pkg.Versions.VersionBound()))
    admitted = intersect(spec, from_current)
    isempty(admitted) || push!(eras, (VERSION, admitted, Pkg.Types.stdlib_infos()))

    return eras
end

# Highest version bound strictly below `v`, the inclusive upper end of the
# release range covered by one STDLIBS_BY_VERSION entry
function bound_below(v::VersionNumber)
    v.patch > 0 && return Pkg.Versions.VersionBound(v.major, v.minor, v.patch - 1)
    v.minor > 0 && return Pkg.Versions.VersionBound(v.major, v.minor - 1)
    v.major > 0 && return Pkg.Versions.VersionBound(v.major - 1)
    return Pkg.Versions.VersionBound(0, 0, 0)
end

"""
    julia_versions_for_compat(julia_compat) -> Vector{VersionNumber}

Representative Julia releases admitted by `julia_compat`, one per era.
"""
julia_versions_for_compat(julia_compat) = VersionNumber[era[1] for era in stdlib_eras(julia_compat)]

"""
    is_stdlib_for_julia_versions(uuid, julia_versions) -> Bool

Whether Pkg treats `uuid` as a standard library, current or former, in any of
`julia_versions`.
"""
function is_stdlib_for_julia_versions(uuid::Base.UUID, julia_versions::Vector{VersionNumber})
    # Upgradable stdlibs (DelimitedFiles, Statistics) are reported as ordinary
    # registry packages by newer Julia releases; Pkg only learns their UUIDs
    # while loading the running Julia's stdlib list
    Pkg.Types.stdlib_infos()
    return any(julia_version -> Pkg.Types.is_or_was_stdlib(uuid, julia_version), julia_versions)
end

"""
    stdlib_versions_for_julia_compat(uuid, julia_compat) -> Vector{VersionNumber}

The versions of stdlib `uuid` a project admitting `julia_compat` has to accept,
reduced to the lowest one per caret-compatible line: the bundled version where
the package is a pinned stdlib (the Julia version itself when the stdlib is
unversioned, which is how Pkg resolves it), or the newest installable registry
release where it is upgradable or not yet a stdlib. Includes v0.0.0 when the
range reaches releases whose test sandbox pins stdlibs to 0.0.0.
"""
function stdlib_versions_for_julia_compat(uuid::Base.UUID, julia_compat::Union{Nothing, Pkg.Versions.VersionSpec})
    eras = stdlib_eras(julia_compat)
    isempty(eras) && return VersionNumber[]

    versions = Set{VersionNumber}()
    registry_versions = registry_versions_with_julia_compat(uuid)
    for (_, admitted, stdlibs) in eras
        info = get(stdlibs, uuid, nothing)
        if info !== nothing
            push!(versions, something(info.version, lowest_version(admitted)))
        else
            installable = [v for (v, julia_spec) in registry_versions if !isempty(intersect(julia_spec, admitted))]
            isempty(installable) || push!(versions, maximum(installable))
        end
    end

    spec = something(julia_compat, Pkg.Versions.VersionSpec())
    before_fix = Pkg.Versions.VersionSpec(Pkg.Versions.VersionRange(Pkg.Versions.VersionBound(), bound_below(STDLIB_TEST_SANDBOX_FIXED)))
    isempty(intersect(spec, before_fix)) || push!(versions, v"0.0.0")

    return lowest_per_line(versions)
end

# Non-yanked registry releases of `uuid` with the Julia versions each admits
function registry_versions_with_julia_compat(uuid::Base.UUID)
    result = Pair{VersionNumber, Pkg.Versions.VersionSpec}[]
    for reg in Pkg.Registry.reachable_registries()
        entry = get(reg, uuid, nothing)
        entry === nothing && continue
        info = registry_info(reg, entry)
        for (v, version_info) in info.version_info
            version_info.yanked && continue
            # The registry stores compat compressed by version range; Pkg 1.13
            # dropped the per-version `compat_info` view, so intersect the
            # ranges covering `v` here
            julia_spec = Pkg.Versions.VersionSpec()
            for (range, compat) in info.compat
                v in range || continue
                julia_spec = intersect(julia_spec, get(compat, JULIA_UUID, Pkg.Versions.VersionSpec()))
            end
            push!(result, v => julia_spec)
        end
    end
    return result
end

function lowest_version(spec::Pkg.Versions.VersionSpec)
    return minimum(VersionNumber(r.lower[1], r.lower[2], r.lower[3]) for r in spec.ranges if !isempty(r))
end

# Caret compatibility: versions sharing a leading non-zero component (or the
# 0.0.x patch) are interchangeable for a compat entry, so only the lowest of
# each line needs to be listed
function lowest_per_line(versions)
    lines = Dict{Tuple{Int, Int, Int}, VersionNumber}()
    for v in versions
        key = v.major > 0 ? (Int(v.major), 0, 0) : v.minor > 0 ? (0, Int(v.minor), 0) : (0, 0, Int(v.patch))
        lines[key] = min(v, get(lines, key, v))
    end
    return sort!(collect(values(lines)))
end

"""
    julia_compat_spec(project::Pkg.Types.Project)

The project's `julia` compat entry as a `VersionSpec`, or `nothing` when absent.
"""
function julia_compat_spec(project::Pkg.Types.Project)
    haskey(project.compat, "julia") || return nothing
    compat = project.compat["julia"]
    return compat isa Pkg.Types.Compat ? compat.val : Pkg.Types.semver_spec(string(compat))
end
