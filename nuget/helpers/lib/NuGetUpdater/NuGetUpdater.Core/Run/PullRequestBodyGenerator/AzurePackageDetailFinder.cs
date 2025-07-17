using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal class AzurePackageDetailFinder : IPackageDetailFinder
{
    public string GetCompareUrlPath(string? oldTag, string? newTag)
    {
        // azure devops doesn't support direct tag listing so both parameters are likely to be null, but just in case, this is the correct url format
        if (oldTag is not null && newTag is not null)
        {
            return $"branchCompare?baseVersion=GT{oldTag}&targetVersion=GT{newTag}";
        }

        if (newTag is not null)
        {
            return $"commits?itemVersion=GT{newTag}";
        }

        return "commits";
    }

    public Task<Dictionary<NuGetVersion, (string TagName, string? Details)>> GetReleaseDataForVersionsAsync(string repoName, NuGetVersion oldVersion, NuGetVersion newVersion)
    {
        // azure devops doesn't support direct tag listing
        return Task.FromResult(new Dictionary<NuGetVersion, (string TagName, string? Details)>());
    }

    public string GetReleasesUrlPath() => "tags";
}
