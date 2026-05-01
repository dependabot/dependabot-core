using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Graph;

public class DependencyGrapher
{
    public const string PurlType = "nuget";
    public const string Ecosystem = "nuget";
    public const int SnapshotVersion = 1;
    public const string DetectorName = "dependabot";
    public const string DetectorUrl = "https://github.com/dependabot/dependabot-core";
    public const string DegradedReasonSubdependencyErr = "error fetching sub-dependencies";

    public static DependencySubmissionPayload BuildSubmission(
        WorkspaceDiscoveryResult discovery,
        string jobId,
        string baseCommitSha,
        string branch,
        string detectorVersion,
        string? repoContentsPath = null,
        ILogger? logger = null)
    {
        var manifests = BuildManifests(discovery, repoContentsPath, logger);
        var status = manifests.Count > 0 ? "ok" : "skipped";
        var reason = manifests.Count > 0 ? null : "missing manifest files";
        var scannedManifestPath = $"{Ecosystem}::{NormalizeWorkspacePath(discovery.Path)}";
        var correlator = BuildCorrelator(discovery.Path);

        return new DependencySubmissionPayload
        {
            Version = SnapshotVersion,
            Sha = baseCommitSha,
            Ref = NormalizeRef(branch),
            Job = new DependencySubmissionJob
            {
                Correlator = correlator,
                Id = jobId,
            },
            Detector = new DependencySubmissionDetector
            {
                Name = DetectorName,
                Version = detectorVersion,
                Url = DetectorUrl,
            },
            Manifests = manifests,
            Metadata = new DependencySubmissionMetadata
            {
                Status = status,
                Reason = reason,
                ScannedManifestPath = scannedManifestPath,
            },
        };
    }

    public static DependencySubmissionPayload BuildFailedSubmission(
        string workspacePath,
        string jobId,
        string baseCommitSha,
        string branch,
        string detectorVersion,
        string reason)
    {
        var scannedManifestPath = $"{Ecosystem}::{NormalizeWorkspacePath(workspacePath)}";
        var correlator = BuildCorrelator(workspacePath);

        return new DependencySubmissionPayload
        {
            Version = SnapshotVersion,
            Sha = baseCommitSha,
            Ref = NormalizeRef(branch),
            Job = new DependencySubmissionJob
            {
                Correlator = correlator,
                Id = jobId,
            },
            Detector = new DependencySubmissionDetector
            {
                Name = DetectorName,
                Version = detectorVersion,
                Url = DetectorUrl,
            },
            Manifests = new Dictionary<string, ManifestPayload>(),
            Metadata = new DependencySubmissionMetadata
            {
                Status = "failed",
                Reason = reason,
                ScannedManifestPath = scannedManifestPath,
            },
        };
    }

    internal static Dictionary<string, ManifestPayload> BuildManifests(
        WorkspaceDiscoveryResult discovery,
        string? repoContentsPath = null,
        ILogger? logger = null)
    {
        var manifests = new Dictionary<string, ManifestPayload>();

        foreach (var project in discovery.Projects)
        {
            if (!project.IsSuccess)
            {
                continue;
            }

            var manifestPath = Path.Join(discovery.Path, project.FilePath).FullyNormalizedRootedPath();

            // Try to find and parse project.assets.json for subdependency relationships
            Dictionary<string, HashSet<string>>? relationships = null;
            if (repoContentsPath is not null && logger is not null)
            {
                var assetsPath = AssetsFileParser.FindAssetsFile(repoContentsPath, discovery.Path, project.FilePath);
                if (assetsPath is not null)
                {
                    var knownPackages = new HashSet<string>(
                        project.Dependencies.Where(d => d.Version is not null).Select(d => d.Name),
                        StringComparer.OrdinalIgnoreCase);
                    relationships = AssetsFileParser.ParseDependencyRelationships(assetsPath, knownPackages, logger);
                }
            }

            var resolved = BuildResolvedDependencies(project.Dependencies, relationships);
            if (resolved.Count == 0)
            {
                continue;
            }

            manifests[manifestPath] = new ManifestPayload
            {
                Name = manifestPath,
                File = new ManifestFile
                {
                    SourceLocation = manifestPath.TrimStart('/'),
                },
                Metadata = new ManifestMetadata
                {
                    Ecosystem = Ecosystem,
                },
                Resolved = resolved,
            };
        }

        AddNonProjectManifest(manifests, discovery.Path, discovery.GlobalJson);
        AddNonProjectManifest(manifests, discovery.Path, discovery.DotNetToolsJson);

        return manifests;
    }

    private static void AddNonProjectManifest(
        Dictionary<string, ManifestPayload> manifests,
        string workspacePath,
        IDiscoveryResultWithDependencies? result)
    {
        if (result is null || !result.IsSuccess)
        {
            return;
        }

        var resolved = BuildResolvedDependencies(result.Dependencies);
        if (resolved.Count == 0)
        {
            return;
        }

        var manifestPath = Path.Join(workspacePath, result.FilePath).FullyNormalizedRootedPath();
        manifests[manifestPath] = new ManifestPayload
        {
            Name = manifestPath,
            File = new ManifestFile
            {
                SourceLocation = manifestPath.TrimStart('/'),
            },
            Metadata = new ManifestMetadata
            {
                Ecosystem = Ecosystem,
            },
            Resolved = resolved,
        };
    }

    internal static Dictionary<string, ResolvedDependencyPayload> BuildResolvedDependencies(
        IEnumerable<Dependency> dependencies,
        Dictionary<string, HashSet<string>>? relationships = null)
    {
        var resolved = new Dictionary<string, ResolvedDependencyPayload>();

        // First pass: build all PURLs so we can reference them in subdependencies
        var depsByName = new Dictionary<string, (Dependency Dep, string Purl)>(StringComparer.OrdinalIgnoreCase);
        foreach (var dep in dependencies)
        {
            if (dep.Version is null)
            {
                continue;
            }

            var purl = BuildPurl(dep.Name, dep.Version);
            depsByName[dep.Name] = (dep, purl);
        }

        // Second pass: build resolved dependencies with subdependency PURLs
        foreach (var (name, (dep, purl)) in depsByName)
        {
            var relationship = dep.IsTopLevel ? "direct" : "indirect";
            var scope = GetScope(dep.Type);

            // Look up subdependencies and convert to PURLs
            var subdepPurls = Array.Empty<string>();
            if (relationships is not null && relationships.TryGetValue(name, out var childNames))
            {
                subdepPurls = childNames
                    .Where(childName => depsByName.ContainsKey(childName))
                    .Select(childName => depsByName[childName].Purl)
                    .OrderBy(p => p, StringComparer.OrdinalIgnoreCase)
                    .ToArray();
            }

            resolved[purl] = new ResolvedDependencyPayload
            {
                PackageUrl = purl,
                Relationship = relationship,
                Scope = scope,
                Dependencies = subdepPurls,
            };
        }

        return resolved;
    }

    internal static string BuildPurl(string name, string version)
    {
        return $"pkg:{PurlType}/{name}@{version}";
    }

    internal static string GetScope(DependencyType type)
    {
        return type switch
        {
            DependencyType.DotNetTool => "development",
            DependencyType.MSBuildSdk => "development",
            _ => "runtime",
        };
    }

    internal static string NormalizeRef(string branch)
    {
        if (branch.TrimStart('/').StartsWith("ref", StringComparison.OrdinalIgnoreCase))
        {
            return branch.TrimStart('/');
        }

        return $"refs/heads/{branch}";
    }

    internal static string BuildCorrelator(string workspacePath)
    {
        var basePart = $"{DetectorName}-nuget";
        var normalizedPath = NormalizeWorkspacePath(workspacePath);
        var dirname = normalizedPath.TrimStart('/');

        if (string.IsNullOrEmpty(dirname))
        {
            return basePart;
        }

        var sanitizedPath = dirname.Length > 32
            ? Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(dirname))).ToLowerInvariant()
            : dirname.Replace('/', '-');

        return $"{basePart}-{sanitizedPath}";
    }

    private static string NormalizeWorkspacePath(string path)
    {
        var normalized = path.FullyNormalizedRootedPath();
        // Ensure it starts with /
        if (!normalized.StartsWith('/'))
        {
            normalized = "/" + normalized;
        }
        return normalized;
    }
}
