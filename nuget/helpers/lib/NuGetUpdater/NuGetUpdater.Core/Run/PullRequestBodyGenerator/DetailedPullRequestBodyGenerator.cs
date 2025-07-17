using System.Collections.Immutable;
using System.Text;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

namespace NuGetUpdater.Core.Run.PullRequestBodyGenerator;

internal class DetailedPullRequestBodyGenerator : IPullRequestBodyGenerator, IDisposable
{
    private readonly IHttpFetcher _httpFetcher;

    public DetailedPullRequestBodyGenerator(IHttpFetcher httpFetcher)
    {
        _httpFetcher = httpFetcher;
    }

    public void Dispose()
    {
        _httpFetcher.Dispose();
    }

    public async Task<string> GeneratePullRequestBodyTextAsync(Job job, ImmutableArray<UpdateOperationBase> updateOperationsPerformed, ImmutableArray<ReportedDependency> updatedDependencies)
    {
        var sb = new StringBuilder();
        var dedupedUpdateOperations = updateOperationsPerformed
            .DistinctBy(u => $"{u.DependencyName}/{u.OldVersion}/{u.NewVersion}", StringComparer.OrdinalIgnoreCase)
            .OrderBy(u => u.DependencyName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(u => u.OldVersion, NullableNuGetVersionComparer.Instance)
            .ThenBy(u => u.NewVersion)
            .ToImmutableArray();
        foreach (var updateOperation in dedupedUpdateOperations)
        {
            if (sb.Length > 0)
            {
                // ensure a blank line between entries
                sb.AppendLine();
            }

            var reportText = $"{updateOperation.GetReport(includeFileNames: false)}.";
            var updatedDependency = updatedDependencies
                .Where(d => d.Name.Equals(updateOperation.DependencyName, StringComparison.OrdinalIgnoreCase))
                .Where(d => NuGetVersion.TryParse(d.Version, out var version) && version == updateOperation.NewVersion)
                .FirstOrDefault();
            var sourceUrl = (updatedDependency?.Requirements ?? [])
                .Select(r => r.Source?.SourceUrl)
                .FirstOrDefault(u => u is not null);
            if (sourceUrl is null)
            {
                // no source url, just append the report text
                sb.AppendLine(reportText);
            }
            else
            {
                // build detailed report
                var packageNameIndex = reportText.IndexOf(updateOperation.DependencyName, StringComparison.OrdinalIgnoreCase);
                if (packageNameIndex >= 0)
                {
                    // link the package name
                    sb.AppendLine($"{reportText[..packageNameIndex]}[{updateOperation.DependencyName}]({sourceUrl}){reportText[(packageNameIndex + updateOperation.DependencyName.Length)..]}");
                }
                else
                {
                    sb.AppendLine(reportText);
                }

                // more details
                if (Uri.TryCreate(sourceUrl, UriKind.Absolute, out var uri))
                {
                    IPackageDetailFinder? packageDetailFinder = uri.Host.ToLowerInvariant() switch
                    {
                        "dev.azure.com" => new AzurePackageDetailFinder(),
                        "github.com" => new GitHubPackageDetailFinder(_httpFetcher),
                        "gitlab.com" => new GitLabPackageDetailFinder(_httpFetcher),
                        var host when host.EndsWith(".visualstudio.com") => new AzurePackageDetailFinder(),
                        _ => null,
                    };

                    if (packageDetailFinder is not null &&
                        updateOperation.OldVersion is not null)
                    {
                        var repoName = uri.LocalPath.TrimStart('/');
                        var versionsAndDetails = await packageDetailFinder.GetReleaseDataForVersionsAsync(repoName, updateOperation.OldVersion, updateOperation.NewVersion);
                        var ordered = versionsAndDetails
                            .Where(kv => kv.Key != updateOperation.OldVersion)
                            .OrderByDescending(kv => kv.Key)
                            .ToList();

                        sb.AppendLine();
                        sb.AppendLine("<details>");
                        sb.AppendLine("<summary>Release notes</summary>");

                        var releasesUrlPath = packageDetailFinder.GetReleasesUrlPath();
                        if (releasesUrlPath is not null)
                        {
                            sb.AppendLine();
                            sb.AppendLine($"_Sourced from [{updateOperation.DependencyName}'s releases]({sourceUrl}/{releasesUrlPath})._");
                        }

                        foreach (var (version, (tagName, body)) in ordered)
                        {
                            sb.AppendLine();
                            sb.AppendLine($"## {version}");
                            if (body is not null)
                            {
                                sb.AppendLine();
                                sb.AppendLine(body);
                            }
                        }

                        if (ordered.Count == 0)
                        {
                            sb.AppendLine();
                            sb.AppendLine("No release notes found for this version range.");
                        }

                        string? oldTag = null;
                        if (versionsAndDetails.TryGetValue(updateOperation.OldVersion, out var oldVersionDetails))
                        {
                            oldTag = oldVersionDetails.TagName;
                        }

                        string? newTag = null;
                        if (versionsAndDetails.TryGetValue(updateOperation.NewVersion, out var newVersionDetails))
                        {
                            newTag = newVersionDetails.TagName;
                        }

                        var compareUrlPath = packageDetailFinder.GetCompareUrlPath(oldTag, newTag);
                        sb.AppendLine();
                        sb.AppendLine($"Commits viewable in [compare view]({sourceUrl}/{compareUrlPath}).");
                        sb.AppendLine("</details>");
                    }
                }
            }
        }

        var prBody = sb.ToString().Replace("\r", "").TrimEnd();
        return prBody;
    }

    private class NullableNuGetVersionComparer : IComparer<NuGetVersion?>
    {
        public static readonly NullableNuGetVersionComparer Instance = new();

        public int Compare(NuGetVersion? x, NuGetVersion? y)
        {
            if (x is null && y is null)
            {
                return 0;
            }

            if (x is null)
            {
                return -1;
            }

            if (y is null)
            {
                return 1;
            }

            return x.CompareTo(y);
        }
    }
}
