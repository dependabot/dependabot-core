# Standard library detection for DependabotHelper.jl
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
# 1.11), so the range is reduced to representative releases here and each is
# checked with Pkg.

"""
    julia_versions_for_compat(julia_compat) -> Vector{VersionNumber}

Representative Julia releases admitted by `julia_compat` (a `VersionSpec`),
one for every distinct stdlib set in the admitted range. `nothing`, meaning
the project has no `julia` compat entry, admits every release.
"""
function julia_versions_for_compat(julia_compat::Union{Nothing, Pkg.Versions.VersionSpec})
    spec = something(julia_compat, Pkg.Versions.VersionSpec())
    versions = VersionNumber[]
    isempty(spec) && return versions

    isempty(Pkg.Types.STDLIBS_BY_VERSION) && HistoricalStdlibVersions.register!()
    by_version = Pkg.Types.STDLIBS_BY_VERSION
    # Each entry holds the stdlibs of that release and of every release before
    # the next entry
    for (i, (julia_version, _)) in enumerate(by_version)
        lower = Pkg.Versions.VersionBound(julia_version)
        upper = i < length(by_version) ? bound_below(first(by_version[i + 1])) : Pkg.Versions.VersionBound()
        covered = Pkg.Versions.VersionSpec(Pkg.Versions.VersionRange(lower, upper))
        isempty(intersect(spec, covered)) || push!(versions, julia_version)
    end

    # Releases the historical data does not know about yet are assumed to ship
    # the running Julia's stdlibs
    from_current = Pkg.Versions.VersionSpec(Pkg.Versions.VersionRange(Pkg.Versions.VersionBound(VERSION), Pkg.Versions.VersionBound()))
    isempty(intersect(spec, from_current)) || push!(versions, VERSION)

    return versions
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
    julia_compat_spec(project::Pkg.Types.Project)

The project's `julia` compat entry as a `VersionSpec`, or `nothing` when absent.
"""
function julia_compat_spec(project::Pkg.Types.Project)
    haskey(project.compat, "julia") || return nothing
    compat = project.compat["julia"]
    return compat isa Pkg.Types.Compat ? compat.val : Pkg.Types.semver_spec(string(compat))
end
