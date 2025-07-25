using System.Collections.Immutable;
using System.Text.Json;

using NuGet.Frameworks;
using NuGet.Versioning;

using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core;

/// <summary>
/// Handles package updates for projects containing `<PackageReference>` MSBuild items.
/// </summary>
/// <remarks>
/// PackageReference items can appear in both SDK-style AND non-SDK-style project files.
/// By default, PackageReference is used by [SDK-style] projects targeting .NET Core, .NET Standard, and UWP.
/// By default, packages.config is used by [non-SDK-style] projects targeting .NET Framework; However, they can be migrated to PackageReference too.
/// See: https://learn.microsoft.com/en-us/nuget/consume-packages/package-references-in-project-files#project-type-support
///      https://learn.microsoft.com/en-us/nuget/consume-packages/migrate-packages-config-to-package-reference
///      https://learn.microsoft.com/en-us/nuget/resources/check-project-format
/// </remarks>
internal static class PackageReferenceUpdater
{
    internal static async Task<IEnumerable<UpdateOperationBase>> ComputeUpdateOperations(
        string repoRoot,
        string projectPath,
        string targetFramework,
        ImmutableArray<Dependency> topLevelDependencies,
        ImmutableArray<Dependency> requestedUpdates,
        ImmutableArray<Dependency> resolvedDependencies,
        ILogger logger
    )
    {
        var topLevelNames = topLevelDependencies.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var topLevelVersionStrings = topLevelDependencies.ToDictionary(d => d.Name, d => d.Version!, StringComparer.OrdinalIgnoreCase);
        var requestedVersions = requestedUpdates.ToDictionary(d => d.Name, d => NuGetVersion.Parse(d.Version!), StringComparer.OrdinalIgnoreCase);
        var resolvedVersions = resolvedDependencies
            .Select(d => (d.Name, NuGetVersion.TryParse(d.Version, out var version), version))
            .Where(d => d.Item2)
            .ToDictionary(d => d.Item1, d => d.Item3!, StringComparer.OrdinalIgnoreCase);

        var (packageParents, packageVersions) = await GetPackageGraphForDependencies(repoRoot, projectPath, targetFramework, resolvedDependencies, logger);
        var updateOperations = new List<UpdateOperationBase>();
        foreach (var (requestedDependencyName, requestedDependencyVersion) in requestedVersions)
        {
            var isDependencyTopLevel = topLevelNames.Contains(requestedDependencyName);
            var isDependencyInResolvedSet = resolvedVersions.ContainsKey(requestedDependencyName);
            switch ((isDependencyTopLevel, isDependencyInResolvedSet))
            {
                case (true, true):
                    // direct update performed
                    var resolvedVer = resolvedVersions[requestedDependencyName];
                    updateOperations.Add(new DirectUpdate()
                    {
                        DependencyName = requestedDependencyName,
                        NewVersion = resolvedVer,
                        UpdatedFiles = [],
                    });
                    break;
                case (false, true):
                    // pinned transitive update
                    updateOperations.Add(new PinnedUpdate()
                    {
                        DependencyName = requestedDependencyName,
                        NewVersion = resolvedVersions[requestedDependencyName],
                        UpdatedFiles = [],
                    });
                    break;
                case (false, false):
                    // walk the first parent all the way up to find a top-level dependency that resulted in the desired change
                    string? rootPackageName = null;
                    var currentPackageName = requestedDependencyName;
                    while (packageParents.TryGetValue(currentPackageName, out var parentSet))
                    {
                        currentPackageName = parentSet.First();
                        if (topLevelNames.Contains(currentPackageName))
                        {
                            rootPackageName = currentPackageName;
                            break;
                        }
                    }

                    if (rootPackageName is not null && resolvedVersions.TryGetValue(rootPackageName, out var rootPackageVersion))
                    {
                        // from a few lines up we've already confirmed that `rootPackageName` was a top-level dependency
                        var rootPackageVersionString = topLevelVersionStrings[rootPackageName];
                        if (NuGetVersion.TryParse(rootPackageVersionString, out var resolvedRootPackageVersion)
                            && rootPackageVersion > resolvedRootPackageVersion)
                        {
                            updateOperations.Add(new ParentUpdate()
                            {
                                DependencyName = requestedDependencyName,
                                NewVersion = requestedVersions[requestedDependencyName],
                                UpdatedFiles = [],
                                ParentDependencyName = rootPackageName,
                                ParentNewVersion = packageVersions[rootPackageName],
                            });
                        }
                    }
                    break;
                case (true, false):
                    // dependency is top-level, but not in the resolved versions; this can happen if an unrelated package has a wildcard
                    break;
            }
        }

        return [.. updateOperations];
    }

    private static async Task<(Dictionary<string, HashSet<string>> PackageParents, Dictionary<string, NuGetVersion> PackageVersions)> GetPackageGraphForDependencies(string repoRoot, string projectPath, string targetFramework, ImmutableArray<Dependency> topLevelDependencies, ILogger logger)
    {
        var packageParents = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        var packageVersions = new Dictionary<string, NuGetVersion>(StringComparer.OrdinalIgnoreCase);
        var tempDir = Directory.CreateTempSubdirectory("_package_graph_for_dependencies_");
        try
        {
            // generate project.assets.json
            var parsedTargetFramework = NuGetFramework.Parse(targetFramework);
            var tempProject = await MSBuildHelper.CreateTempProjectAsync(tempDir, repoRoot, projectPath, targetFramework, topLevelDependencies, logger, importDependencyTargets: false);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["build", tempProject, "/t:_ReportDependencies"], tempDir.FullName);
            var assetsJsonPath = Path.Join(tempDir.FullName, "obj", "project.assets.json");
            var assetsJsonContent = await File.ReadAllTextAsync(assetsJsonPath);

            // build reverse dependency graph
            var assets = JsonDocument.Parse(assetsJsonContent).RootElement;
            foreach (var tfmObject in assets.GetProperty("targets").EnumerateObject())
            {
                var reportedTargetFramework = NuGetFramework.Parse(tfmObject.Name);
                if (reportedTargetFramework != parsedTargetFramework)
                {
                    // not interested in this target framework
                    continue;
                }

                foreach (var parentObject in tfmObject.Value.EnumerateObject())
                {
                    var parts = parentObject.Name.Split('/');
                    var parentName = parts[0];
                    var parentVersion = parts[1];
                    packageVersions[parentName] = NuGetVersion.Parse(parentVersion);

                    if (parentObject.Value.TryGetProperty("dependencies", out var dependencies))
                    {
                        foreach (var childObject in dependencies.EnumerateObject())
                        {
                            var childName = childObject.Name;
                            var parentSet = packageParents.GetOrAdd(childName, () => new(StringComparer.OrdinalIgnoreCase));
                            parentSet.Add(parentName);
                        }
                    }
                }
            }

            return (packageParents, packageVersions);
        }
        catch (Exception ex)
        {
            logger.Error($"Error while generating package graph: {ex.Message}");
            throw;
        }
        finally
        {
            tempDir.Delete(recursive: true);
        }
    }
}
