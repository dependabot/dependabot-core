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
        var result = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var packageScopedResult = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var otherPackageScopedResult = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var url = $"https://api.github.com/repos/{repoName}/releases?per_page=100";
        var jsonOption = await _httpFetcher.GetJsonElementAsync(url);
        if (jsonOption is null)
        {
            return result;
        }

        var json = jsonOption.Value;
        if (json.ValueKind != JsonValueKind.Array)
        {
            return result;
        }

        if (json.GetArrayLength() == 0)
        {
            return result;
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
                    packageScopedResult[correspondingVersion] = (tagName, body);
                }
                else if (isOtherPackageScopedVersion)
                {
                    otherPackageScopedResult[correspondingVersion] = (tagName, body);
                }
                else
                {
                    result[correspondingVersion] = (tagName, body);
                }
            }
        }

        if (packageScopedResult.Count > 0)
        {
            foreach (var packageScopedDetails in packageScopedResult)
            {
                result[packageScopedDetails.Key] = packageScopedDetails.Value;
            }

            return result;
        }

        foreach (var otherPackageScopedDetails in otherPackageScopedResult)
        {
            result[otherPackageScopedDetails.Key] = otherPackageScopedDetails.Value;
        }

        return result;
    }

    public string GetReleasesUrlPath() => "releases";
}
