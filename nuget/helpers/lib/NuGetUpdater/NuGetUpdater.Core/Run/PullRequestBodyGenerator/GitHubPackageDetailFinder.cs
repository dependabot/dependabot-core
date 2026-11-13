using System.Text.Json;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal class GitHubPackageDetailFinder : IPackageDetailFinder
{
    private readonly IHttpFetcher _httpFetcher;

    public GitHubPackageDetailFinder(IHttpFetcher httpFetcher)
    {
        _httpFetcher = httpFetcher;
    }

    public string GetCompareUrlPath(string? oldTag, string? newTag)
    {
        if (oldTag is not null && newTag is not null)
        {
            return $"compare/{oldTag}...{newTag}";
        }

        if (newTag is not null)
        {
            return $"commits/{newTag}";
        }

        return "commits";
    }

    public async Task<Dictionary<NuGetVersion, (string TagName, string? Details)>> GetReleaseDataForVersionsAsync(string repoName, string dependencyName, NuGetVersion oldVersion, NuGetVersion newVersion)
    {
        var versionReleaseData = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var packageScopedVersionReleaseData = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var otherPackageScopedVersionReleaseData = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var url = $"https://api.github.com/repos/{repoName}/releases?per_page=100";
        var jsonOption = await _httpFetcher.GetJsonElementAsync(url);
        if (jsonOption is null)
        {
            return versionReleaseData;
        }

        var json = jsonOption.Value;
        if (json.ValueKind != JsonValueKind.Array)
        {
            return versionReleaseData;
        }

        if (json.GetArrayLength() == 0)
        {
            return versionReleaseData;
        }

        foreach (var releaseObject in json.EnumerateArray())
        {
            if (releaseObject.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            // get release name
            if (!releaseObject.TryGetProperty("name", out var releasenameElement) ||
                releasenameElement.ValueKind != JsonValueKind.String)
            {
                continue;
            }

            var releaseName = releasenameElement.GetString()!;

            // get tag name
            if (!releaseObject.TryGetProperty("tag_name", out var tagNameElement) ||
                tagNameElement.ValueKind != JsonValueKind.String)
            {
                continue;
            }

            var tagName = tagNameElement.GetString()!;

            // find matching version
            var packageScopedVersion = IPackageDetailFinder.GetPackageScopedVersionFromNames(releaseName, tagName, dependencyName);
            var correspondingVersion = packageScopedVersion ?? IPackageDetailFinder.GetVersionFromNames(releaseName, tagName);
            var isOtherPackageScopedVersion = packageScopedVersion is null &&
                IPackageDetailFinder.HasPackageScopedVersionForOtherDependency(releaseName, tagName, dependencyName);
            if (correspondingVersion is null)
            {
                continue;
            }

            if (correspondingVersion >= oldVersion && correspondingVersion <= newVersion)
            {
                if (!releaseObject.TryGetProperty("body", out var bodyElement) ||
                bodyElement.ValueKind != JsonValueKind.String)
                {
                    continue;
                }

                var body = bodyElement.GetString()!;
                if (packageScopedVersion is not null)
                {
                    packageScopedVersionReleaseData[correspondingVersion] = (tagName, body);
                }
                else if (isOtherPackageScopedVersion)
                {
                    otherPackageScopedVersionReleaseData[correspondingVersion] = (tagName, body);
                }
                else
                {
                    versionReleaseData[correspondingVersion] = (tagName, body);
                }
            }
        }

        if (packageScopedVersionReleaseData.Count > 0)
        {
            foreach (var packageScopedDetails in packageScopedVersionReleaseData)
            {
                versionReleaseData[packageScopedDetails.Key] = packageScopedDetails.Value;
            }

            return versionReleaseData;
        }

        foreach (var otherPackageScopedDetails in otherPackageScopedVersionReleaseData)
        {
            versionReleaseData[otherPackageScopedDetails.Key] = otherPackageScopedDetails.Value;
        }

        return versionReleaseData;
    }

    public string GetReleasesUrlPath() => "releases";
}
