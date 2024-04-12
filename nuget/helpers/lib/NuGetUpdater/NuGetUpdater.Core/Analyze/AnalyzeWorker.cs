using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Versioning;

using NuGetUpdater.Analyzer;
using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Analyze;

public partial class AnalyzeWorker
{
    public const string AnalysisDirectoryName = "./.dependabot/analysis";

    private readonly Logger _logger;

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(), new RequirementConverter() },
    };

    public AnalyzeWorker(Logger logger)
    {
        _logger = logger;
    }

    public async Task RunAsync(string discoveryPath, string dependencyPath, string analysisDirectory)
    {
        var discovery = LoadDiscovery(discoveryPath);
        var dependencyInfo = LoadDependencyInfo(dependencyPath);

        var nugetContext = CreateNuGetContext();

        var currentVersion = NuGetVersion.Parse(dependencyInfo.Version);
        var projectFrameworks = FindProjectFrameworksForDependency(discovery, dependencyInfo);
        var versions = await VersionFinder.GetVersionsAsync(
            dependencyInfo.Name,
            currentVersion.IsPrerelease,
            nugetContext,
            _logger,
            CancellationToken.None);

        ImmutableArray<Dependency> updatedDependencies = [];
        var updatedVersion = await FindUpdatedVersionAsync(
            discovery,
            dependencyInfo,
            currentVersion,
            projectFrameworks,
            versions,
            nugetContext);
        if (updatedVersion is not null)
        {
            // Determine updated peer dependencies
            var source = versions.GetPackageSources(updatedVersion).First();
            var packageId = new PackageIdentity(dependencyInfo.Name, updatedVersion);

            // Create distinct list of dependencies taking the highest version of each
            Dictionary<string, PackageDependency> dependencies = [];
            foreach (var tfm in projectFrameworks)
            {
                var dependenciesForTfm = await DependencyFinder.GetDependenciesAsync(
                        source,
                        packageId,
                        tfm,
                        nugetContext,
                        _logger,
                        CancellationToken.None);

                foreach (var dependency in dependenciesForTfm)
                {
                    if (dependencies.TryGetValue(dependency.Id, out PackageDependency? value) &&
                        value.VersionRange.MinVersion! < dependency.VersionRange.MinVersion!)
                    {
                        dependencies[dependency.Id] = dependency;
                    }
                    else
                    {
                        dependencies.Add(dependency.Id, dependency);
                    }
                }
            }

            // Filter dependencies by whether any project references them
            updatedDependencies = dependencies
                .Where(dep => discovery.Projects.Any(p => p.Dependencies.Any(d => d.Name.Equals(dep.Key, StringComparison.OrdinalIgnoreCase))))
                .Select(dep => new Dependency(dep.Key, dep.Value.VersionRange.MinVersion!.ToNormalizedString(), DependencyType.Unknown))
                .Prepend(new Dependency(dependencyInfo.Name, updatedVersion.ToNormalizedString(), DependencyType.Unknown))
                .ToImmutableArray();
        }

        var result = new AnalysisResult
        {
            UpdatedVersion = updatedVersion?.ToNormalizedString() ?? dependencyInfo.Version,
            CanUpdate = updatedVersion is not null,
            VersionComesFromMultiDependencyProperty = false, //TODO: Provide correct value
            UpdatedDependencies = updatedDependencies,
        };

        await WriteResultsAsync(analysisDirectory, dependencyInfo.Name, result);
    }

    internal static WorkspaceDiscoveryResult LoadDiscovery(string discoveryPath)
    {
        if (!File.Exists(discoveryPath))
        {
            throw new FileNotFoundException("Discovery file not found.", discoveryPath);
        }

        var discoveryJson = File.ReadAllText(discoveryPath);
        var discovery = JsonSerializer.Deserialize<WorkspaceDiscoveryResult>(discoveryJson, SerializerOptions);
        if (discovery is null)
        {
            throw new InvalidOperationException("Discovery file is empty.");
        }

        return discovery;
    }

    internal static DependencyInfo LoadDependencyInfo(string dependencyPath)
    {
        if (!File.Exists(dependencyPath))
        {
            throw new FileNotFoundException("Dependency info file not found.", dependencyPath);
        }

        var dependencyInfoJson = File.ReadAllText(dependencyPath);
        var dependencyInfo = JsonSerializer.Deserialize<DependencyInfo>(dependencyInfoJson, SerializerOptions);
        if (dependencyInfo is null)
        {
            throw new InvalidOperationException("Dependency info file is empty.");
        }

        return dependencyInfo;
    }

    internal static NuGetContext CreateNuGetContext()
    {
        var nugetContext = new NuGetContext();
        if (!Directory.Exists(nugetContext.TempPackageDirectory))
        {
            Directory.CreateDirectory(nugetContext.TempPackageDirectory);
        }

        return nugetContext;
    }

    internal async Task<NuGetVersion?> FindUpdatedVersionAsync(
        WorkspaceDiscoveryResult discovery,
        DependencyInfo dependencyInfo,
        NuGetVersion currentVersion,
        ImmutableArray<NuGetFramework> projectFrameworks,
        VersionResult versions,
        NuGetContext nugetContext)
    {
        var allVersions = versions.GetVersions();

        var filteredVersions = allVersions
            .Where(version => version > currentVersion) // filter lower versions
            .Where(version => !currentVersion.IsPrerelease || !version.IsPrerelease || version.Version == currentVersion.Version) // filter prerelease
            .Where(version => !dependencyInfo.IgnoredVersions.Any(r => r.IsSatisfiedBy(version))) // filter ignored
            .Where(version => !dependencyInfo.Vulnerabilities.Any(v => v.IsVulnerable(version))); // filter vulnerable

        var orderedVersions = dependencyInfo.IsVulnerable
            ? filteredVersions.OrderBy(v => v) // If we are fixing a vulnerability, then we want the lowest version that is safe.
            : filteredVersions.OrderByDescending(v => v); // If we are just updating versions, then we want the highest version possible.

        return await FindFirstCompatibleVersion(
            dependencyInfo.Name,
            currentVersion,
            versions,
            orderedVersions,
            projectFrameworks,
            nugetContext,
            _logger);
    }

    internal static ImmutableArray<NuGetFramework> FindProjectFrameworksForDependency(WorkspaceDiscoveryResult discovery, DependencyInfo dependencyInfo)
    {
        return discovery.Projects
            .Where(p => p.Dependencies.Any(d => d.Name.Equals(dependencyInfo.Name, StringComparison.OrdinalIgnoreCase)))
            .SelectMany(p => p.TargetFrameworks)
            .Distinct()
            .Select(tfm => NuGetFramework.Parse(tfm))
            .ToImmutableArray();
    }

    internal static async Task<NuGetVersion?> FindFirstCompatibleVersion(
        string packageId,
        NuGetVersion currentVersion,
        VersionResult versions,
        IEnumerable<NuGetVersion> orderedVersions,
        ImmutableArray<NuGetFramework> projectFrameworks,
        NuGetContext context,
        Logger logger)
    {
        var source = versions.GetPackageSources(currentVersion).First();
        var isCompatible = await CompatibilityChecker.CheckAsync(
            source,
            new(packageId, currentVersion),
            projectFrameworks,
            context,
            logger,
            CancellationToken.None);
        if (!isCompatible)
        {
            // If the current package is incompatible, then don't check for compatibility.
            return orderedVersions.First();
        }

        foreach (var version in orderedVersions)
        {
            source = versions.GetPackageSources(version).First();
            isCompatible = await CompatibilityChecker.CheckAsync(
                source,
                new(packageId, version),
                projectFrameworks,
                context,
                logger,
                CancellationToken.None);

            if (isCompatible)
            {
                return version;
            }
        }

        // Could not find a compatible version
        return null;
    }

    internal static async Task WriteResultsAsync(string analysisDirectory, string dependencyName, AnalysisResult result)
    {
        if (!Directory.Exists(analysisDirectory))
        {
            Directory.CreateDirectory(analysisDirectory);
        }

        var resultPath = Path.Combine(analysisDirectory, $"{dependencyName}.json");
        var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
        await File.WriteAllTextAsync(path: resultPath, resultJson);
    }
}
