using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public enum RequirementsUpdateStrategy
{
    [JsonStringEnumMemberName("bump_versions")]
    BumpVersions,
    [JsonStringEnumMemberName("bump_versions_if_necessary")]
    BumpVersionsIfNecessary,
    [JsonStringEnumMemberName("lockfile_only")]
    LockfileOnly,
    [JsonStringEnumMemberName("widen_ranges")]
    WidenRanges,
}
