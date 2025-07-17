using System.Text.Json;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal class GitLabPackageDetailFinder : IPackageDetailFinder
{
    private readonly IHttpFetcher _httpFetcher;

    public GitLabPackageDetailFinder(IHttpFetcher httpFetcher)
    {
        _httpFetcher = httpFetcher;
    }

    public string GetCompareUrlPath(string? oldTag, string? newTag)
    {
        if (oldTag is not null && newTag is not null)
        {
            return $"-/compare/{oldTag}...{newTag}";
        }

        if (newTag is not null)
        {
            return $"-/commits/{newTag}";
        }

        return "-/commits";
    }

    public async Task<Dictionary<NuGetVersion, (string TagName, string? Details)>> GetReleaseDataForVersionsAsync(string repoName, NuGetVersion oldVersion, NuGetVersion newVersion)
    {
        var result = new Dictionary<NuGetVersion, (string TagName, string? Details)>();
        var url = $"https://gitlab.com/api/v4/projects/{Uri.EscapeDataString(repoName)}/repository/tags";
        var jsonString = await _httpFetcher.GetStringAsync(url);
        if (jsonString is null)
        {
            return result;
        }

        JsonElement json;
        try
        {
            json = JsonSerializer.Deserialize<JsonElement>(jsonString);
        }
        catch (JsonException)
        {
            return result;
        }

        if (json.ValueKind != JsonValueKind.Array)
        {
            return result;
        }

        if (json.GetArrayLength() == 0)
        {
            return result;
        }

        foreach (var responseObject in json.EnumerateArray())
        {
            if (responseObject.ValueKind != JsonValueKind.Object)
            {
                continue;
            }

            // get release name
            if (!responseObject.TryGetProperty("name", out var releaseNameElement) ||
                releaseNameElement.ValueKind != JsonValueKind.String)
            {
                continue;
            }

            var releaseName = releaseNameElement.GetString()!;

            // get release info
            string? tagName = null;
            string? description = null;
            if (responseObject.TryGetProperty("release", out var releaseObject) &&
                releaseObject.ValueKind == JsonValueKind.Object)
            {
                if (releaseObject.TryGetProperty("tag_name", out var tagNameElement) &&
                    tagNameElement.ValueKind == JsonValueKind.String)
                {
                    tagName = tagNameElement.GetString()!;
                }

                if (releaseObject.TryGetProperty("description", out var descriptionElement) &&
                    descriptionElement.ValueKind == JsonValueKind.String)
                {
                    description = descriptionElement.GetString();
                }
            }

            // find matching version
            var correspondingVersion = IPackageDetailFinder.GetVersionFromNames(releaseName, tagName);
            if (correspondingVersion is null)
            {
                continue;
            }

            var resultTag = tagName ?? releaseName;
            if (resultTag is not null &&
                correspondingVersion >= oldVersion &&
                correspondingVersion <= newVersion)
            {
                result[correspondingVersion] = (resultTag, description);
            }
        }

        return result;
    }

    public string GetReleasesUrlPath() => "-/releases";
}
