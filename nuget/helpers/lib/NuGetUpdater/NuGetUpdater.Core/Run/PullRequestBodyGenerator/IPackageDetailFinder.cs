using System.Text.RegularExpressions;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal partial interface IPackageDetailFinder
{
    string GetReleasesUrlPath();
    string GetCompareUrlPath(string? oldTag, string? newTag);
    Task<Dictionary<NuGetVersion, (string TagName, string? Details)>> GetReleaseDataForVersionsAsync(string repoName, NuGetVersion oldVersion, NuGetVersion newVersion);

    internal static NuGetVersion? GetVersionFromNames(string? releaseName, string? tagName)
    {
        foreach (var candidateName in new[] { releaseName, tagName }.Where(n => n is not null).Cast<string>())
        {
            var trimmedName = NamePrefixPattern.Replace(candidateName, string.Empty);
            if (NuGetVersion.TryParse(trimmedName, out var versionFromTrimmed))
            {
                return versionFromTrimmed;
            }
        }

        return null;
    }

    [GeneratedRegex(@"^[^0-9]*")]
    private static partial Regex NamePrefixRemover();

    private static readonly Regex NamePrefixPattern = NamePrefixRemover();
}
