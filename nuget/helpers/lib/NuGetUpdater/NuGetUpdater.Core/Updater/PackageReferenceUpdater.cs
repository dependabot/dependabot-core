using System.Collections.Immutable;
using System.Text.Json;

using Microsoft.Language.Xml;

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
    public static async Task<IEnumerable<UpdateOperationBase>> UpdateDependencyAsync(
        string repoRootPath,
        string projectPath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        bool isTransitive,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        // PackageReference project; modify the XML directly
        logger.Info("  Running 'PackageReference' project direct XML update");

        (ImmutableArray<ProjectBuildFile> buildFiles, string[] tfms) = await MSBuildHelper.LoadBuildFilesAndTargetFrameworksAsync(repoRootPath, projectPath);

        // Get the set of all top-level dependencies in the current project
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles).ToArray();
        var isDependencyTopLevel = topLevelDependencies.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (isDependencyTopLevel)
        {
            var packageMapper = DotNetPackageCorrelationManager.GetPackageMapper();
            // TODO: this is slow
            var isSdkReplacementPackage = packageMapper.RuntimePackages.Runtimes.Any(r =>
            {
                return r.Value.Packages.Any(p => dependencyName.Equals(p.Key, StringComparison.Ordinal));
            });
            if (isSdkReplacementPackage)
            {
                // If we're updating a top level SDK replacement package, the version listed in the project file won't
                // necessarily match the resolved version that caused the update because the SDK might have replaced
                // the package.  To handle this scenario, we pretend the version we're searching for is the actual
                // version in the file, not the resolved version.  This allows us to keep a strict equality check when
                // finding the file to update.
                previousDependencyVersion = topLevelDependencies.First(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase)).Version!;
            }
        }

        if (!await DoesDependencyRequireUpdateAsync(repoRootPath, projectPath, tfms, topLevelDependencies, dependencyName, newDependencyVersion, experimentsManager, logger))
        {
            return [];
        }

        var updateOperations = new List<UpdateOperationBase>();
        var peerDependencies = await GetUpdatedPeerDependenciesAsync(repoRootPath, projectPath, tfms, dependencyName, newDependencyVersion, experimentsManager, logger);
        if (experimentsManager.UseLegacyDependencySolver)
        {
            if (isTransitive)
            {
                var updatedFiles = await UpdateTransitiveDependencyAsync(repoRootPath, projectPath, dependencyName, newDependencyVersion, buildFiles, experimentsManager, logger);
                updateOperations.Add(new PinnedUpdate()
                {
                    DependencyName = dependencyName,
                    NewVersion = NuGetVersion.Parse(newDependencyVersion),
                    UpdatedFiles = [.. updatedFiles],
                });
            }
            else
            {
                if (peerDependencies is null)
                {
                    return updateOperations;
                }

                var topLevelUpdateOperations = await UpdateTopLevelDepdendency(repoRootPath, buildFiles, tfms, dependencyName, previousDependencyVersion, newDependencyVersion, peerDependencies, experimentsManager, logger);
                updateOperations.AddRange(topLevelUpdateOperations);
            }
        }
        else
        {
            if (peerDependencies is null)
            {
                return updateOperations;
            }

            var conflictResolutionUpdateOperations = await UpdateDependencyWithConflictResolution(
                repoRootPath,
                buildFiles,
                tfms,
                projectPath,
                dependencyName,
                previousDependencyVersion,
                newDependencyVersion,
                isTransitive,
                peerDependencies,
                experimentsManager,
                logger);
            updateOperations.AddRange(conflictResolutionUpdateOperations);
        }

        if (!await AreDependenciesCoherentAsync(repoRootPath, projectPath, dependencyName, buildFiles, tfms, experimentsManager, logger))
        {
            // should we return an empty set because we failed?
            return updateOperations;
        }

        await SaveBuildFilesAsync(buildFiles, logger);
        return updateOperations;
    }

    public static async Task<IEnumerable<UpdateOperationBase>> UpdateDependencyWithConflictResolution(
        string repoRootPath,
        ImmutableArray<ProjectBuildFile> buildFiles,
        string[] targetFrameworks,
        string projectPath,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        bool isTransitive,
        IDictionary<string, string> peerDependencies,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles).ToImmutableArray();
        var isDependencyTopLevel = topLevelDependencies.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        var dependenciesToUpdate = new[] { new Dependency(dependencyName, newDependencyVersion, DependencyType.PackageReference) }.ToImmutableArray();
        var updateOperations = new List<UpdateOperationBase>();

        // update the initial dependency...
        var (_, updateOperationsPerformed) = TryUpdateDependencyVersion(buildFiles, dependencyName, previousDependencyVersion, newDependencyVersion, logger);
        updateOperations.AddRange(updateOperationsPerformed);

        // ...and the peer dependencies...
        foreach (var (packageName, packageVersion) in peerDependencies.Where(kvp => string.Compare(kvp.Key, dependencyName, StringComparison.OrdinalIgnoreCase) != 0))
        {
            (_, updateOperationsPerformed) = TryUpdateDependencyVersion(buildFiles, packageName, previousDependencyVersion: null, newDependencyVersion: packageVersion, logger);
            updateOperations.AddRange(updateOperationsPerformed);
        }

        // ...and everything else
        foreach (var projectFile in buildFiles)
        {
            foreach (var tfm in targetFrameworks)
            {
                var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflicts(repoRootPath, projectFile.Path, tfm, topLevelDependencies, dependenciesToUpdate, experimentsManager, logger);
                if (resolvedDependencies is null)
                {
                    logger.Warn($"    Unable to resolve dependency conflicts for {projectFile.Path}.");
                    continue;
                }

                var isDependencyInResolutionSet = resolvedDependencies.Value.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
                if (isTransitive && !isDependencyTopLevel && isDependencyInResolutionSet)
                {
                    // a transitive dependency had to be pinned; add it here
                    var updatedFiles = await UpdateTransitiveDependencyAsync(repoRootPath, projectPath, dependencyName, newDependencyVersion, buildFiles, experimentsManager, logger);
                }

                // update all resolved dependencies that aren't the initial dependency
                foreach (var resolvedDependency in resolvedDependencies.Value
                                                    .Where(d => !d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
                                                    .Where(d => d.Version is not null))
                {
                    (_, updateOperationsPerformed) = TryUpdateDependencyVersion(buildFiles, resolvedDependency.Name, previousDependencyVersion: null, newDependencyVersion: resolvedDependency.Version!, logger);
                    updateOperations.AddRange(updateOperationsPerformed);
                }

                updateOperationsPerformed = await ComputeUpdateOperations(repoRootPath, projectPath, tfm, topLevelDependencies, dependenciesToUpdate, resolvedDependencies.Value, experimentsManager, logger);
                updateOperations.AddRange(updateOperationsPerformed.Select(u => u with { UpdatedFiles = [projectFile.Path] }));
            }
        }

        return updateOperations;
    }

    internal static async Task<IEnumerable<UpdateOperationBase>> ComputeUpdateOperations(
        string repoRoot,
        string projectPath,
        string targetFramework,
        ImmutableArray<Dependency> topLevelDependencies,
        ImmutableArray<Dependency> requestedUpdates,
        ImmutableArray<Dependency> resolvedDependencies,
        ExperimentsManager experimentsManager,
        ILogger logger
    )
    {
        var topLevelNames = topLevelDependencies.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var requestedVersions = requestedUpdates.ToDictionary(d => d.Name, d => NuGetVersion.Parse(d.Version!), StringComparer.OrdinalIgnoreCase);
        var resolvedVersions = resolvedDependencies
            .Select(d => (d.Name, NuGetVersion.TryParse(d.Version, out var version), version))
            .Where(d => d.Item2)
            .ToDictionary(d => d.Item1, d => d.Item3!, StringComparer.OrdinalIgnoreCase);

        var (packageParents, packageVersions) = await GetPackageGraphForDependencies(repoRoot, projectPath, targetFramework, resolvedDependencies, experimentsManager, logger);
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

                    if (rootPackageName is not null)
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
                    break;
                case (true, false):
                    // dependency is top-level, but not in the resolved versions; this can happen if an unrelated package has a wildcard
                    break;
            }
        }

        return [.. updateOperations];
    }

    private static async Task<(Dictionary<string, HashSet<string>> PackageParents, Dictionary<string, NuGetVersion> PackageVersions)> GetPackageGraphForDependencies(string repoRoot, string projectPath, string targetFramework, ImmutableArray<Dependency> topLevelDependencies, ExperimentsManager experimentsManager, ILogger logger)
    {
        var packageParents = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
        var packageVersions = new Dictionary<string, NuGetVersion>(StringComparer.OrdinalIgnoreCase);
        var tempDir = Directory.CreateTempSubdirectory("_package_graph_for_dependencies_");
        try
        {
            // generate project.assets.json
            var parsedTargetFramework = NuGetFramework.Parse(targetFramework);
            var tempProject = await MSBuildHelper.CreateTempProjectAsync(tempDir, repoRoot, projectPath, targetFramework, topLevelDependencies, experimentsManager, logger, importDependencyTargets: !experimentsManager.UseDirectDiscovery);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["build", tempProject, "/t:_ReportDependencies"], tempDir.FullName, experimentsManager);
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

    /// <summary>
    /// Verifies that the package does not already satisfy the requested dependency version.
    /// </summary>
    /// <returns>Returns false if the package is not found or does not need to be updated.</returns>
    private static async Task<bool> DoesDependencyRequireUpdateAsync(
        string repoRootPath,
        string projectPath,
        string[] tfms,
        Dependency[] topLevelDependencies,
        string dependencyName,
        string newDependencyVersion,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        var newDependencyNuGetVersion = NuGetVersion.Parse(newDependencyVersion);

        bool packageFound = false;
        bool needsUpdate = false;

        foreach (var tfm in tfms)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                repoRootPath,
                projectPath,
                tfm,
                topLevelDependencies,
                experimentsManager,
                logger);
            foreach (var dependency in dependencies)
            {
                var packageName = dependency.Name;
                var packageVersion = dependency.Version;
                if (packageVersion is null)
                {
                    continue;
                }

                if (packageName.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
                {
                    packageFound = true;

                    var nugetVersion = NuGetVersion.Parse(packageVersion);
                    if (nugetVersion < newDependencyNuGetVersion)
                    {
                        needsUpdate = true;
                        break;
                    }
                }
            }

            if (packageFound && needsUpdate)
            {
                break;
            }
        }

        // Skip updating the project if the dependency does not exist in the graph
        if (!packageFound)
        {
            logger.Info($"    Package [{dependencyName}] Does not exist as a dependency in [{projectPath}].");
            return false;
        }

        // Skip updating the project if the dependency version meets or exceeds the newDependencyVersion
        if (!needsUpdate)
        {
            logger.Info($"    Package [{dependencyName}] already meets the requested dependency version in [{projectPath}].");
            return false;
        }

        return true;
    }

    /// <returns>The updated files.</returns>
    internal static async Task<IEnumerable<string>> UpdateTransitiveDependencyAsync(
        string repoRootPath,
        string projectPath,
        string dependencyName,
        string newDependencyVersion,
        ImmutableArray<ProjectBuildFile> buildFiles,
        ExperimentsManager experimentsManager,
        ILogger logger
    )
    {
        IEnumerable<string> updatedFiles;
        var directoryPackagesWithPinning = buildFiles.OfType<ProjectBuildFile>()
            .FirstOrDefault(bf => IsCpmTransitivePinningEnabled(bf));
        if (directoryPackagesWithPinning is not null)
        {
            updatedFiles = PinTransitiveDependency(directoryPackagesWithPinning, dependencyName, newDependencyVersion, logger);
        }
        else
        {
            updatedFiles = await AddTransitiveDependencyAsync(repoRootPath, projectPath, dependencyName, newDependencyVersion, experimentsManager, logger);

            // files directly modified on disk by an external tool need to be refreshed in-memory
            foreach (var updatedFile in updatedFiles)
            {
                var matchingBuildFile = buildFiles.FirstOrDefault(bf => PathComparer.Instance.Compare(updatedFile, bf.Path) == 0);
                if (matchingBuildFile is not null)
                {
                    var updatedContents = await File.ReadAllTextAsync(updatedFile);
                    matchingBuildFile.Update(ProjectBuildFile.Parse(updatedContents));
                }
            }
        }

        return updatedFiles;
    }

    private static bool IsCpmTransitivePinningEnabled(ProjectBuildFile buildFile)
    {
        var buildFileName = Path.GetFileName(buildFile.Path);
        if (!buildFileName.Equals("Directory.Packages.props", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var propertyElements = buildFile.PropertyNodes;

        var isCpmEnabledValue = propertyElements.FirstOrDefault(e =>
            e.Name.Equals("ManagePackageVersionsCentrally", StringComparison.OrdinalIgnoreCase))?.GetContentValue();
        if (isCpmEnabledValue is null || !string.Equals(isCpmEnabledValue, "true", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var isTransitivePinningEnabled = propertyElements.FirstOrDefault(e =>
            e.Name.Equals("CentralPackageTransitivePinningEnabled", StringComparison.OrdinalIgnoreCase))?.GetContentValue();
        return isTransitivePinningEnabled is not null && string.Equals(isTransitivePinningEnabled, "true", StringComparison.OrdinalIgnoreCase);
    }

    /// <returns>The updated files.</returns>
    private static IEnumerable<string> PinTransitiveDependency(ProjectBuildFile directoryPackages, string dependencyName, string newDependencyVersion, ILogger logger)
    {
        var existingPackageVersionElement = directoryPackages.ItemNodes
            .Where(e => e.Name.Equals("PackageVersion", StringComparison.OrdinalIgnoreCase) &&
                        e.Attributes.Any(a => a.Name.Equals("Include", StringComparison.OrdinalIgnoreCase) &&
                                              a.Value.Equals(dependencyName, StringComparison.OrdinalIgnoreCase)))
            .FirstOrDefault();

        logger.Info($"    Pinning [{dependencyName}/{newDependencyVersion}] as a package version.");

        var lastPackageVersion = directoryPackages.ItemNodes
            .Where(e => e.Name.Equals("PackageVersion", StringComparison.OrdinalIgnoreCase))
            .LastOrDefault();

        if (lastPackageVersion is null)
        {
            logger.Info($"    Transitive dependency [{dependencyName}/{newDependencyVersion}] was not pinned.");
            return [];
        }

        var lastItemGroup = lastPackageVersion.Parent;

        IXmlElementSyntax updatedItemGroup;
        if (existingPackageVersionElement is null)
        {
            // need to add a new entry
            logger.Info("      New PackageVersion element added.");
            var leadingTrivia = lastPackageVersion.AsNode.GetLeadingTrivia();
            var packageVersionElement = XmlExtensions.CreateSingleLineXmlElementSyntax("PackageVersion", new SyntaxList<SyntaxNode>(leadingTrivia))
                .WithAttribute("Include", dependencyName)
                .WithAttribute("Version", newDependencyVersion);
            updatedItemGroup = lastItemGroup.AddChild(packageVersionElement);
        }
        else
        {
            IXmlElementSyntax updatedPackageVersionElement;
            var versionAttribute = existingPackageVersionElement.Attributes.FirstOrDefault(a => a.Name.Equals("Version", StringComparison.OrdinalIgnoreCase));
            if (versionAttribute is null)
            {
                // need to add the version
                logger.Info("      Adding version attribute to element.");
                updatedPackageVersionElement = existingPackageVersionElement.WithAttribute("Version", newDependencyVersion);
            }
            else if (!versionAttribute.Value.Equals(newDependencyVersion, StringComparison.OrdinalIgnoreCase))
            {
                // need to update the version
                logger.Info($"      Updating version attribute of [{versionAttribute.Value}].");
                var updatedVersionAttribute = versionAttribute.WithValue(newDependencyVersion);
                updatedPackageVersionElement = existingPackageVersionElement.ReplaceAttribute(versionAttribute, updatedVersionAttribute);
            }
            else
            {
                logger.Info("      Existing PackageVersion element version was already correct.");
                return [];
            }

            updatedItemGroup = lastItemGroup.ReplaceChildElement(existingPackageVersionElement, updatedPackageVersionElement);
        }

        var updatedXml = directoryPackages.Contents.ReplaceNode(lastItemGroup.AsNode, updatedItemGroup.AsNode);
        directoryPackages.Update(updatedXml);

        return [directoryPackages.Path];
    }

    /// <returns>The updated files.</returns>
    private static async Task<IEnumerable<string>> AddTransitiveDependencyAsync(string repoRootPath, string projectPath, string dependencyName, string newDependencyVersion, ExperimentsManager experimentsManager, ILogger logger)
    {
        var updatedFiles = new[] { projectPath }; // assume this worked unless...
        var projectDirectory = Path.GetDirectoryName(projectPath)!;
        await MSBuildHelper.HandleGlobalJsonAsync(projectDirectory, repoRootPath, experimentsManager, async () =>
        {
            logger.Info($"    Adding [{dependencyName}/{newDependencyVersion}] as a top-level package reference.");

            // see https://learn.microsoft.com/nuget/consume-packages/install-use-packages-dotnet-cli
            var (exitCode, stdout, stderr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(
                ["add", projectPath, "package", dependencyName, "--version", newDependencyVersion],
                projectDirectory,
                experimentsManager
            );
            MSBuildHelper.ThrowOnError(stdout);
            if (exitCode != 0)
            {
                logger.Warn($"    Transitive dependency [{dependencyName}/{newDependencyVersion}] was not added.\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}");
                updatedFiles = [];
            }

            return exitCode;
        }, logger, retainMSBuildSdks: true);

        return updatedFiles;
    }

    /// <summary>
    /// Gets the set of peer dependencies that need to be updated.
    /// </summary>
    /// <returns>Returns null if there are conflicting versions.</returns>
    private static async Task<Dictionary<string, string>?> GetUpdatedPeerDependenciesAsync(
        string repoRootPath,
        string projectPath,
        string[] tfms,
        string dependencyName,
        string newDependencyVersion,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        var newDependency = new[] { new Dependency(dependencyName, newDependencyVersion, DependencyType.Unknown) };
        var tfmsAndDependencies = new Dictionary<string, ImmutableArray<Dependency>>();
        foreach (var tfm in tfms)
        {
            var dependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, projectPath, tfm, newDependency, experimentsManager, logger);
            tfmsAndDependencies[tfm] = dependencies;
        }

        var unupgradableTfms = tfmsAndDependencies.Where(kvp => !kvp.Value.Any()).Select(kvp => kvp.Key);
        if (unupgradableTfms.Any())
        {
            logger.Info($"    The following target frameworks could not find packages to upgrade: {string.Join(", ", unupgradableTfms)}");
            return null;
        }

        var conflictingPackageVersionsFound = false;
        var packagesAndVersions = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (_, dependencies) in tfmsAndDependencies)
        {
            foreach (var dependency in dependencies)
            {
                var packageName = dependency.Name;
                var packageVersion = dependency.Version;
                if (packagesAndVersions.TryGetValue(packageName, out var existingVersion) &&
                    existingVersion != packageVersion)
                {
                    logger.Info($"    Package [{packageName}] tried to update to version [{packageVersion}], but found conflicting package version of [{existingVersion}].");
                    conflictingPackageVersionsFound = true;
                }
                else
                {
                    packagesAndVersions[packageName] = packageVersion!;
                }
            }
        }

        // stop update process if we find conflicting package versions
        if (conflictingPackageVersionsFound)
        {
            return null;
        }

        return packagesAndVersions;
    }

    private static async Task<IEnumerable<UpdateOperationBase>> UpdateTopLevelDepdendency(
        string repoRootPath,
        ImmutableArray<ProjectBuildFile> buildFiles,
        string[] targetFrameworks,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        IDictionary<string, string> peerDependencies,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        // update dependencies...
        var updateOperations = new List<UpdateOperationBase>();
        var (updateResult, updateOperationsPerformed) = TryUpdateDependencyVersion(buildFiles, dependencyName, previousDependencyVersion, newDependencyVersion, logger);
        if (updateResult == UpdateResult.NotFound)
        {
            logger.Info($"    Root package [{dependencyName}/{previousDependencyVersion}] was not updated; skipping dependencies.");
            return [];
        }

        updateOperations.AddRange(updateOperationsPerformed);

        foreach (var (packageName, packageVersion) in peerDependencies.Where(kvp => string.Compare(kvp.Key, dependencyName, StringComparison.OrdinalIgnoreCase) != 0))
        {
            (_, updateOperationsPerformed) = TryUpdateDependencyVersion(buildFiles, packageName, previousDependencyVersion: null, newDependencyVersion: packageVersion, logger);
            updateOperations.AddRange(updateOperationsPerformed);
        }

        // ...and make them all coherent
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles).ToImmutableArray();
        foreach (ProjectBuildFile projectFile in buildFiles)
        {
            foreach (string tfm in targetFrameworks)
            {
                var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsWithBruteForce(repoRootPath, projectFile.Path, tfm, topLevelDependencies, experimentsManager, logger);
                if (resolvedDependencies is null)
                {
                    logger.Info($"    Unable to resolve dependency conflicts for {projectFile.Path}.");
                    continue;
                }

                // ensure the originally requested dependency was resolved to the correct version
                var specificResolvedDependency = resolvedDependencies.Value.Where(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase)).FirstOrDefault();
                if (specificResolvedDependency is null)
                {
                    logger.Info($"    Unable to resolve requested dependency for {dependencyName} in {projectFile.Path}.");
                    continue;
                }

                if (!newDependencyVersion.Equals(specificResolvedDependency.Version, StringComparison.OrdinalIgnoreCase))
                {
                    logger.Info($"    Inconsistent resolution for {dependencyName}; attempted upgrade to {newDependencyVersion} but resolved {specificResolvedDependency.Version}.");
                    continue;
                }

                // update all versions
                foreach (Dependency resolvedDependency in resolvedDependencies.Value
                                                          .Where(d => !d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
                                                          .Where(d => d.Version is not null))
                {
                    (_, updateOperationsPerformed) = TryUpdateDependencyVersion(buildFiles, resolvedDependency.Name, previousDependencyVersion: null, newDependencyVersion: resolvedDependency.Version!, logger);
                    updateOperations.AddRange(updateOperationsPerformed);
                }

                updateOperationsPerformed = await ComputeUpdateOperations(repoRootPath, projectFile.Path, tfm, topLevelDependencies, [new Dependency(dependencyName, newDependencyVersion, DependencyType.PackageReference)], resolvedDependencies.Value, experimentsManager, logger);
                updateOperations.AddRange(updateOperationsPerformed.Select(u => u with { UpdatedFiles = [projectFile.Path] }));
            }
        }

        return updateOperations;
    }

    /// <returns>The updated files.</returns>
    internal static (UpdateResult, IEnumerable<UpdateOperationBase>) TryUpdateDependencyVersion(
        ImmutableArray<ProjectBuildFile> buildFiles,
        string dependencyName,
        string? previousDependencyVersion,
        string newDependencyVersion,
        ILogger logger)
    {
        var foundCorrect = false;
        var foundUnsupported = false;
        var updateWasPerformed = false;
        var propertyNames = new List<string>();
        var updateOperations = new List<UpdateOperationBase>();

        // First we locate all the PackageReference, GlobalPackageReference, or PackageVersion which set the Version
        // or VersionOverride attribute. In the simplest case we can update the version attribute directly then move
        // on. When property substitution is used we have to additionally search for the property containing the version.

        foreach (var buildFile in buildFiles)
        {
            var updateNodes = new List<XmlNodeSyntax>();
            var packageNodes = FindPackageNodes(buildFile, dependencyName);

            var previousPackageVersion = previousDependencyVersion;

            foreach (var packageNode in packageNodes)
            {
                var versionAttribute = packageNode.GetAttribute("Version", StringComparison.OrdinalIgnoreCase)
                                       ?? packageNode.GetAttribute("VersionOverride", StringComparison.OrdinalIgnoreCase);
                var versionElement = packageNode.Elements.FirstOrDefault(e => e.Name.Equals("Version", StringComparison.OrdinalIgnoreCase))
                                     ?? packageNode.Elements.FirstOrDefault(e => e.Name.Equals("VersionOverride", StringComparison.OrdinalIgnoreCase));
                if (versionAttribute is not null)
                {
                    // Is this the case where version is specified with property substitution?
                    if (MSBuildHelper.TryGetPropertyName(versionAttribute.Value, out var propertyName))
                    {
                        propertyNames.Add(propertyName);
                    }
                    // Is this the case that the version is specified directly in the package node?
                    else
                    {
                        var currentVersion = versionAttribute.Value.TrimStart('[', '(').TrimEnd(']', ')');
                        if (currentVersion.Contains(',') || currentVersion.Contains('*'))
                        {
                            logger.Warn($"    Found unsupported [{packageNode.Name}] version attribute value [{versionAttribute.Value}] in [{buildFile.RelativePath}].");
                            foundUnsupported = true;
                        }
                        else if (string.Equals(currentVersion, previousDependencyVersion, StringComparison.Ordinal))
                        {
                            logger.Info($"    Found incorrect [{packageNode.Name}] version attribute in [{buildFile.RelativePath}].");
                            updateNodes.Add(versionAttribute);
                            updateOperations.Add(new DirectUpdate()
                            {
                                DependencyName = dependencyName,
                                NewVersion = NuGetVersion.Parse(newDependencyVersion),
                                UpdatedFiles = [buildFile.Path],
                            });
                        }
                        else if (previousDependencyVersion == null && NuGetVersion.TryParse(currentVersion, out var previousVersion))
                        {
                            var newVersion = NuGetVersion.Parse(newDependencyVersion);
                            if (previousVersion < newVersion)
                            {
                                previousPackageVersion = currentVersion;

                                logger.Info($"    Found incorrect peer [{packageNode.Name}] version attribute in [{buildFile.RelativePath}].");
                                updateNodes.Add(versionAttribute);
                                updateOperations.Add(new DirectUpdate()
                                {
                                    DependencyName = dependencyName,
                                    NewVersion = NuGetVersion.Parse(newDependencyVersion),
                                    UpdatedFiles = [buildFile.Path],
                                });
                            }
                        }
                        else if (string.Equals(currentVersion, newDependencyVersion, StringComparison.Ordinal))
                        {
                            logger.Info($"    Found correct [{packageNode.Name}] version attribute in [{buildFile.RelativePath}].");
                            foundCorrect = true;
                        }
                    }
                }
                else if (versionElement is not null)
                {
                    var versionValue = versionElement.GetContentValue();
                    if (MSBuildHelper.TryGetPropertyName(versionValue, out var propertyName))
                    {
                        propertyNames.Add(propertyName);
                    }
                    else
                    {
                        var currentVersion = versionValue.TrimStart('[', '(').TrimEnd(']', ')');
                        if (currentVersion.Contains(',') || currentVersion.Contains('*'))
                        {
                            logger.Info($"    Found unsupported [{packageNode.Name}] version node value [{versionValue}] in [{buildFile.RelativePath}].");
                            foundUnsupported = true;
                        }
                        else if (currentVersion == previousDependencyVersion)
                        {
                            logger.Info($"    Found incorrect [{packageNode.Name}] version node in [{buildFile.RelativePath}].");
                            if (versionElement is XmlElementSyntax elementSyntax)
                            {
                                updateNodes.Add(elementSyntax);
                                updateOperations.Add(new DirectUpdate()
                                {
                                    DependencyName = dependencyName,
                                    NewVersion = NuGetVersion.Parse(newDependencyVersion),
                                    UpdatedFiles = [buildFile.Path],
                                });
                            }
                            else
                            {
                                throw new InvalidDataException("A concrete type was required for updateNodes. This should not happen.");
                            }
                        }
                        else if (previousDependencyVersion == null && NuGetVersion.TryParse(currentVersion, out var previousVersion))
                        {
                            var newVersion = NuGetVersion.Parse(newDependencyVersion);
                            if (previousVersion < newVersion)
                            {
                                previousPackageVersion = currentVersion;

                                logger.Info($"    Found incorrect peer [{packageNode.Name}] version node in [{buildFile.RelativePath}].");
                                if (versionElement is XmlElementSyntax elementSyntax)
                                {
                                    updateNodes.Add(elementSyntax);
                                    updateOperations.Add(new DirectUpdate()
                                    {
                                        DependencyName = dependencyName,
                                        NewVersion = NuGetVersion.Parse(newDependencyVersion),
                                        UpdatedFiles = [buildFile.Path],
                                    });
                                }
                                else
                                {
                                    // This only exists for completeness in case we ever add a new type of node we don't want to silently ignore them.
                                    throw new InvalidDataException("A concrete type was required for updateNodes. This should not happen.");
                                }
                            }
                        }
                        else if (currentVersion == newDependencyVersion)
                        {
                            logger.Info($"    Found correct [{packageNode.Name}] version node in [{buildFile.RelativePath}].");
                            foundCorrect = true;
                        }
                    }
                }
                else
                {
                    // We weren't able to find the version node. Central package management?
                    logger.Warn("    Found package reference but was unable to locate version information.");
                }
            }

            if (updateNodes.Count > 0)
            {
                var updatedXml = buildFile.Contents
                    .ReplaceNodes(updateNodes, (_, n) =>
                    {
                        if (n is XmlAttributeSyntax attributeSyntax)
                        {
                            return attributeSyntax.WithValue(attributeSyntax.Value.Replace(previousPackageVersion!, newDependencyVersion));
                        }

                        if (n is XmlElementSyntax elementsSyntax)
                        {
                            var modifiedContent = elementsSyntax.GetContentValue().Replace(previousPackageVersion!, newDependencyVersion);

                            var textSyntax = SyntaxFactory.XmlText(SyntaxFactory.Token(null, SyntaxKind.XmlTextLiteralToken, null, modifiedContent));
                            return elementsSyntax.WithContent(SyntaxFactory.SingletonList(textSyntax));
                        }

                        throw new InvalidDataException($"Unsupported SyntaxType {n.GetType().Name} marked for update");
                    });
                buildFile.Update(updatedXml);
                updateWasPerformed = true;
            }
        }

        // If property substitution was used to set the Version, we must search for the property containing
        // the version string. Since it could also be populated by property substitution this search repeats
        // with the each new property name until the version string is located.

        var processedPropertyNames = new HashSet<string>();

        for (int propertyNameIndex = 0; propertyNameIndex < propertyNames.Count; propertyNameIndex++)
        {
            var propertyName = propertyNames[propertyNameIndex];
            if (processedPropertyNames.Contains(propertyName))
            {
                continue;
            }

            processedPropertyNames.Add(propertyName);

            foreach (var buildFile in buildFiles)
            {
                var updateProperties = new List<XmlElementSyntax>();
                var propertyElements = buildFile.PropertyNodes
                    .Where(e => e.Name.Equals(propertyName, StringComparison.OrdinalIgnoreCase));

                var previousPackageVersion = previousDependencyVersion;

                foreach (var propertyElement in propertyElements)
                {
                    var propertyContents = propertyElement.GetContentValue();

                    // Is this the case where this property contains another property substitution?
                    if (MSBuildHelper.TryGetPropertyName(propertyContents, out var propName))
                    {
                        propertyNames.Add(propName);
                    }
                    // Is this the case that the property contains the version?
                    else
                    {
                        var currentVersion = propertyContents.TrimStart('[', '(').TrimEnd(']', ')');
                        if (currentVersion.Contains(',') || currentVersion.Contains('*'))
                        {
                            logger.Warn($"    Found unsupported version property [{propertyElement.Name}] value [{propertyContents}] in [{buildFile.RelativePath}].");
                            foundUnsupported = true;
                        }
                        else if (currentVersion == previousDependencyVersion)
                        {
                            logger.Info($"    Found incorrect version property [{propertyElement.Name}] in [{buildFile.RelativePath}].");
                            updateProperties.Add((XmlElementSyntax)propertyElement.AsNode);
                        }
                        else if (previousDependencyVersion is null && NuGetVersion.TryParse(currentVersion, out var previousVersion))
                        {
                            var newVersion = NuGetVersion.Parse(newDependencyVersion);
                            if (previousVersion < newVersion)
                            {
                                previousPackageVersion = currentVersion;

                                logger.Info($"    Found incorrect peer version property [{propertyElement.Name}] in [{buildFile.RelativePath}].");
                                updateProperties.Add((XmlElementSyntax)propertyElement.AsNode);
                            }
                        }
                        else if (currentVersion == newDependencyVersion)
                        {
                            logger.Info($"    Found correct version property [{propertyElement.Name}] in [{buildFile.RelativePath}].");
                            foundCorrect = true;
                        }
                    }
                }

                if (updateProperties.Count > 0)
                {
                    var updatedXml = buildFile.Contents
                        .ReplaceNodes(updateProperties, (o, n) => n.WithContent(o.GetContentValue().Replace(previousPackageVersion!, newDependencyVersion)).AsNode);
                    buildFile.Update(updatedXml);
                    updateWasPerformed = true;
                }
            }
        }

        var updateResult = updateWasPerformed
            ? UpdateResult.Updated
            : foundCorrect
                ? UpdateResult.Correct
                : foundUnsupported
                    ? UpdateResult.NotSupported
                    : UpdateResult.NotFound;
        return (updateResult, updateOperations);
    }

    private static IEnumerable<IXmlElementSyntax> FindPackageNodes(
        ProjectBuildFile buildFile,
        string packageName)
        => buildFile.PackageItemNodes.Where(e =>
        {
            // Attempt to get "Include" or "Update" attribute values
            var includeOrUpdateValue = e.GetAttributeOrSubElementValue("Include", StringComparison.OrdinalIgnoreCase)
                                    ?? e.GetAttributeOrSubElementValue("Update", StringComparison.OrdinalIgnoreCase);
            // Trim and split if there's a valid value
            var packageNames = includeOrUpdateValue?
                                .Trim()
                                .Split(';', StringSplitOptions.RemoveEmptyEntries)
                                .Select(t => t.Trim())
                                .Where(t => t.Equals(packageName.Trim(), StringComparison.OrdinalIgnoreCase));
            // Check if there's a matching package name and a non-null version attribute
            return packageNames?.Any() == true &&
                (e.GetAttributeOrSubElementValue("Version", StringComparison.OrdinalIgnoreCase)
                    ?? e.GetAttributeOrSubElementValue("VersionOverride", StringComparison.OrdinalIgnoreCase)) is not null;
        });

    private static async Task<bool> AreDependenciesCoherentAsync(
        string repoRootPath,
        string projectPath,
        string dependencyName,
        ImmutableArray<ProjectBuildFile> buildFiles,
        string[] tfms,
        ExperimentsManager experimentsManager,
        ILogger logger
    )
    {
        var updatedTopLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles).ToArray();
        foreach (var tfm in tfms)
        {
            var updatedPackages = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, projectPath, tfm, updatedTopLevelDependencies, experimentsManager, logger);
            var dependenciesAreCoherent = await MSBuildHelper.DependenciesAreCoherentAsync(repoRootPath, projectPath, tfm, updatedPackages, experimentsManager, logger);
            if (!dependenciesAreCoherent)
            {
                logger.Warn($"    Package [{dependencyName}] could not be updated in [{projectPath}] because it would cause a dependency conflict.");
                return false;
            }
        }

        return true;
    }

    private static async Task SaveBuildFilesAsync(ImmutableArray<ProjectBuildFile> buildFiles, ILogger logger)
    {
        foreach (var buildFile in buildFiles)
        {
            if (await buildFile.SaveAsync())
            {
                logger.Info($"    Saved [{buildFile.RelativePath}].");
            }
        }
    }
}
