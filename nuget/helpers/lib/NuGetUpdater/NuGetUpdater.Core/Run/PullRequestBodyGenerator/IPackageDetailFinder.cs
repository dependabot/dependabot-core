using System.Text.RegularExpressions;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal partial interface IPackageDetailFinder
{
    string GetReleasesUrlPath();
    string GetCompareUrlPath(string? oldTag, string? newTag);
    Task<Dictionary<NuGetVersion, (string TagName, string? Details)>> GetReleaseDataForVersionsAsync(string repoName, string dependencyName, NuGetVersion oldVersion, NuGetVersion newVersion);

    internal static NuGetVersion? GetVersionFromNames(string? releaseName, string? tagName, string? dependencyName = null)
    {
        if (dependencyName is not null)
        {
            var packageScopedVersion = GetPackageScopedVersionFromNames(releaseName, tagName, dependencyName);
            if (packageScopedVersion is not null)
            {
                return packageScopedVersion;
            }
        }

        return GetRepoScopedVersionFromNames(releaseName, tagName);
    }

    internal static NuGetVersion? GetPackageScopedVersionFromNames(string? releaseName, string? tagName, string dependencyName)
    {
        foreach (var candidateName in new[] { releaseName, tagName }.Where(n => n is not null).Cast<string>())
        {
            var trimmedCandidateName = candidateName.Trim();
            var match = Regex.Match(
                trimmedCandidateName,
                $@"(?:^|[\s/_-]){Regex.Escape(dependencyName)}[\s/_-]+v?(?<version>[0-9][A-Za-z0-9.+-]*)$",
                RegexOptions.IgnoreCase);
            if (!match.Success)
            {
                continue;
            }

            var version = match.Groups["version"].Value;
            if (NuGetVersion.TryParse(version, out var versionFromPackageScopedName))
            {
                return versionFromPackageScopedName;
            }
        }

        return null;
    }

    internal static bool HasPackageScopedVersionForOtherDependency(string? releaseName, string? tagName, string dependencyName)
    {
        foreach (var candidateName in new[] { releaseName, tagName }.Where(n => n is not null).Cast<string>())
        {
            var trimmedCandidateName = candidateName.Trim();
            var match = PackageScopedNamePattern.Match(trimmedCandidateName);
            if (!match.Success)
            {
                continue;
            }

            var matchedDependencyName = match.Groups["dependency"].Value;
            var version = match.Groups["version"].Value;
            if (!matchedDependencyName.Contains('.') ||
                matchedDependencyName.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) ||
                !NuGetVersion.TryParse(version, out _))
            {
                continue;
            }

            return true;
        }

        return false;
    }

    private static NuGetVersion? GetRepoScopedVersionFromNames(string? releaseName, string? tagName)
    {
        foreach (var candidateName in new[] { releaseName, tagName }.Where(n => n is not null).Cast<string>())
        {
            var trimmedName = NamePrefixPattern.Replace(candidateName.Trim(), string.Empty);
            if (NuGetVersion.TryParse(trimmedName, out var versionFromTrimmed))
            {
                return versionFromTrimmed;
            }
        }

        return null;
    }

    [GeneratedRegex(@"^[^0-9]*")]
    private static partial Regex NamePrefixRemover();

    [GeneratedRegex(@"(?:^|[\s/_-])(?<dependency>[A-Za-z0-9_.-]+)[\s/_-]+v?(?<version>[0-9][A-Za-z0-9.+-]*)$", RegexOptions.IgnoreCase)]
    private static partial Regex PackageScopedNameMatcher();

    private static readonly Regex NamePrefixPattern = NamePrefixRemover();

    private static readonly Regex PackageScopedNamePattern = PackageScopedNameMatcher();
}
