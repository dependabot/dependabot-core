using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal interface IPackageDetailFinder
{
    string GetReleasesUrlPath();
    string GetCompareUrlPath(string? oldTag, string? newTag);
    Task<Dictionary<NuGetVersion, (string TagName, string? Details)>> GetReleaseDataForVersionsAsync(string repoName, NuGetVersion oldVersion, NuGetVersion newVersion);

    internal static NuGetVersion? GetVersionFromNames(string? releaseName, string? tagName)
    {
        var prefixesToTrim = new[]
        {
            "version-",
            "version.",
            "version ",
            "version",
            "v-",
            "v.",
            "v ",
            "v",
        };
        foreach (var candidateName in new[] { releaseName, tagName }.Where(n => n is not null).Cast<string>())
        {
            foreach (var prefix in prefixesToTrim)
            {
                if (candidateName.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
                {
                    var trimmedCandidateName = candidateName[prefix.Length..];
                    if (NuGetVersion.TryParse(trimmedCandidateName, out var versionFromTrimmed))
                    {
                        return versionFromTrimmed;
                    }
                }
            }

            // no prefix match, try the whole string
            if (NuGetVersion.TryParse(candidateName, out var versionFromWhole))
            {
                return versionFromWhole;
            }
        }

        return null;
    }
}
