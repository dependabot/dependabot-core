using System.Collections.Immutable;
using System.Text.Json;
using System.Xml.Linq;
using System.Xml.XPath;

using Microsoft.Build.Logging.StructuredLogger;

using NuGet.Frameworks;

using NuGetUpdater.Core.Utilities;

using Semver;

using LoggerProperty = Microsoft.Build.Logging.StructuredLogger.Property;

namespace NuGetUpdater.Core.Discover;

internal static class SdkProjectDiscovery
{
    private static readonly HashSet<string> TopLevelPackageItemNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "PackageReference"
    };

    private static readonly HashSet<string> PackageVersionItemNames = new HashSet<string>(StringComparer.Ordinal)
    {
        "PackageVersion"
    };

    // the items listed below represent collection names that NuGet will resolve a package into, along with the metadata value names to get the package name and version
    private static readonly Dictionary<string, (string NameMetadata, string VersionMetadata)> ResolvedPackageItemNames = new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase)
    {
        ["NativeCopyLocalItems"] = ("NuGetPackageId", "NuGetPackageVersion"),
        ["ResourceCopyLocalItems"] = ("NuGetPackageId", "NuGetPackageVersion"),
        ["RuntimeCopyLocalItems"] = ("NuGetPackageId", "NuGetPackageVersion"),
        ["ResolvedAnalyzers"] = ("NuGetPackageId", "NuGetPackageVersion"),
        ["_PackageDependenciesDesignTime"] = ("Name", "Version"),
    };

    // these packages are resolved during restore, but aren't really updatable and shouldn't be reported as dependencies
    private static readonly HashSet<string> NonReportedPackgeNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "Microsoft.NETCore.Platforms",
        "Microsoft.NETCore.Targets",
        "NETStandard.Library"
    };

    // these are additional files that are relevant to the project and need to be reported
    private static readonly HashSet<string> AdditionalFileNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "packages.config",
        "app.config",
        "web.config",
    };

    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverAsync(string repoRootPath, string workspacePath, string startingProjectPath, ExperimentsManager experimentsManager, ILogger logger)
    {
        // N.b., there are many paths used in this function.  The MSBuild binary log always reports fully qualified paths, so that's what will be used
        // throughout until the very end when the appropriate kind of relative path is returned.

        // step through the binlog one item at a time
        var startingProjectDirectory = Path.GetDirectoryName(startingProjectPath)!;

        // the following collection feature heavily; the shape is described as follows

        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesPerProject = new(PathComparer.Instance);
        //    projectPath                tfm        packageName  packageVersion

        Dictionary<string, Dictionary<string, HashSet<string>>> topLevelPackagesPerProject = new(PathComparer.Instance);
        //    projectPath                tfm, packageNames

        Dictionary<string, Dictionary<string, Dictionary<string, string>>> explicitPackageVersionsPerProject = new(PathComparer.Instance);
        //    projectPath,               tfm,       packageName, packageVersion

        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesReplacedBySdkPerProject = new(PathComparer.Instance);
        //    projectPath                tfm        packageName  packageVersion

        Dictionary<string, Dictionary<string, HashSet<string>>> packageDependencies = new(PathComparer.Instance);
        //    projectPath                tfm  packageNames

        Dictionary<string, Dictionary<string, string>> resolvedProperties = new(PathComparer.Instance);
        //    projectPath       propertyName  propertyValue

        Dictionary<string, HashSet<string>> importedFiles = new(PathComparer.Instance);
        //    projectPath  importedFiles

        Dictionary<string, HashSet<string>> referencedProjects = new(PathComparer.Instance);
        //    projectPath  referencedProjects

        Dictionary<string, HashSet<string>> additionalFiles = new(PathComparer.Instance);
        //    projectPath  additionalFiles

        var requiresManualPackageResolution = false;
        var tfms = await MSBuildHelper.GetTargetFrameworkValuesFromProject(repoRootPath, startingProjectPath, experimentsManager, logger);
        foreach (var tfm in tfms)
        {
            // create a binlog
            var binLogPath = Path.Combine(Path.GetTempPath(), $"msbuild_{Guid.NewGuid():d}.binlog");
            try
            {
                // TODO: once the updater image has all relevant SDKs installed, we won't have to sideline global.json anymore
                var (exitCode, stdOut, stdErr) = await MSBuildHelper.HandleGlobalJsonAsync(startingProjectDirectory, repoRootPath, experimentsManager, async () =>
                {
                    // the built-in target `GenerateBuildDependencyFile` forces resolution of all NuGet packages, but doesn't invoke a full build
                    var dependencyDiscoveryTargetingPacksPropsPath = MSBuildHelper.GetFileFromRuntimeDirectory("DependencyDiscoveryTargetingPacks.props");
                    var dependencyDiscoveryTargetsPath = MSBuildHelper.GetFileFromRuntimeDirectory("DependencyDiscovery.targets");
                    var args = new List<string>()
                    {
                        "build",
                        startingProjectPath,
                        "/t:_DiscoverDependencies",
                        $"/p:TargetFramework={tfm}",
                        $"/p:CustomBeforeMicrosoftCommonProps={dependencyDiscoveryTargetingPacksPropsPath}",
                        $"/p:CustomAfterMicrosoftCommonCrossTargetingTargets={dependencyDiscoveryTargetsPath}",
                        $"/p:CustomAfterMicrosoftCommonTargets={dependencyDiscoveryTargetsPath}",
                        "/p:TreatWarningsAsErrors=false", // if using CPM and a project also sets TreatWarningsAsErrors to true, this can cause discovery to fail; explicitly don't allow that
                        "/p:MSBuildTreatWarningsAsErrors=false",
                        $"/bl:{binLogPath}"
                    };
                    var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(args, startingProjectDirectory, experimentsManager);
                    if (exitCode != 0 && stdOut.Contains("error : Object reference not set to an instance of an object."))
                    {
                        // https://github.com/NuGet/Home/issues/11761#issuecomment-1105218996
                        // Due to a bug in NuGet, there can be a null reference exception thrown and adding this command line argument will work around it,
                        // but this argument can't always be added; it can cause problems in other instances, so we're taking the approach of not using it
                        // unless we have to.
                        args.Add("/RestoreProperty:__Unused__=__Unused__");
                        (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(args, startingProjectDirectory, experimentsManager);
                    }

                    return (exitCode, stdOut, stdErr);
                }, logger, retainMSBuildSdks: true);
                MSBuildHelper.ThrowOnError(stdOut);
                if (stdOut.Contains("_DependencyDiscovery_LegacyProjects::UseTemporaryProject"))
                {
                    // special case - legacy project with <PackageReference> elements; this requires extra handling below
                    requiresManualPackageResolution = true;
                }
                if (exitCode != 0)
                {
                    // log error, but still try to resolve what we can
                    logger.Warn($"  Error determining dependencies from `{startingProjectPath}`:\nSTDOUT:\n{stdOut}\nSTDERR:\n{stdErr}");
                }

                var buildRoot = BinaryLog.ReadBuild(binLogPath);
                buildRoot.VisitAllChildren<BaseNode>(node =>
                {
                    switch (node)
                    {
                        case LoggerProperty property:
                            {
                                var projectEvaluation = property.GetNearestParent<ProjectEvaluation>();
                                if (projectEvaluation is not null)
                                {
                                    var properties = resolvedProperties.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));
                                    properties[property.Name] = property.Value;
                                }
                            }
                            break;
                        case Import import:
                            {
                                var projectEvaluation = GetNearestProjectEvaluation(import);
                                if (projectEvaluation is not null)
                                {
                                    // props and targets files might have been imported from these, but they're not to be considered as dependency files
                                    var forbiddenDirectories = new[]
                                        {
                                            GetPropertyValueFromProjectEvaluation(projectEvaluation, "BaseIntermediateOutputPath"), // e.g., "obj/"
                                            GetPropertyValueFromProjectEvaluation(projectEvaluation, "BaseOutputPath"), // e.g., "bin/"
                                        }
                                        .Where(p => !string.IsNullOrEmpty(p))
                                        .Select(p => Path.Combine(Path.GetDirectoryName(projectEvaluation.ProjectFile)!, p!))
                                        .Select(p => p.NormalizePathToUnix())
                                        .Select(p => new DirectoryInfo(p))
                                        .ToArray();
                                    if (PathHelper.IsFileUnderDirectory(new DirectoryInfo(repoRootPath), new FileInfo(import.ImportedProjectFilePath)))
                                    {
                                        if (!forbiddenDirectories.Any(f => PathHelper.IsFileUnderDirectory(f, new FileInfo(import.ImportedProjectFilePath))))
                                        {
                                            var imports = importedFiles.GetOrAdd(projectEvaluation.ProjectFile, () => new(PathComparer.Instance));
                                            imports.Add(import.ImportedProjectFilePath);
                                        }
                                    }
                                }
                            }
                            break;
                        case NamedNode namedNode when namedNode is AddItem or RemoveItem:
                            ProcessResolvedPackageReference(namedNode, packagesPerProject, topLevelPackagesPerProject, explicitPackageVersionsPerProject, experimentsManager);

                            if (namedNode is AddItem addItem)
                            {
                                // maintain list of project references
                                if (addItem.Name.Equals("ProjectReference", StringComparison.OrdinalIgnoreCase))
                                {
                                    var projectEvaluation = GetNearestProjectEvaluation(addItem);
                                    if (projectEvaluation is not null)
                                    {
                                        foreach (var referencedProject in addItem.Children.OfType<Item>())
                                        {
                                            var referencedProjectPaths = referencedProjects.GetOrAdd(projectEvaluation.ProjectFile, () => new(PathComparer.Instance));
                                            var referencedProjectPath = new FileInfo(Path.Combine(Path.GetDirectoryName(projectEvaluation.ProjectFile)!, referencedProject.Name)).FullName;
                                            referencedProjectPaths.Add(referencedProjectPath);
                                        }
                                    }
                                }

                                // maintain list of additional files
                                if (addItem.Name.Equals("None", StringComparison.OrdinalIgnoreCase) ||
                                    addItem.Name.Equals("Content", StringComparison.OrdinalIgnoreCase))
                                {
                                    var projectEvaluation = GetNearestProjectEvaluation(addItem);
                                    if (projectEvaluation is not null)
                                    {
                                        foreach (var additionalItem in addItem.Children.OfType<Item>())
                                        {
                                            if (AdditionalFileNames.Contains(additionalItem.Name))
                                            {
                                                var additionalFilesForProject = additionalFiles.GetOrAdd(projectEvaluation.ProjectFile, () => new(PathComparer.Instance));
                                                var additionalFilePath = new FileInfo(Path.Combine(Path.GetDirectoryName(projectEvaluation.ProjectFile)!, additionalItem.Name)).FullName;
                                                additionalFilesForProject.Add(additionalFilePath);
                                            }
                                        }
                                    }
                                }

                                // track all referenced projects in case they have no assemblies and can't be otherwise reported
                                if (addItem.Name.Equals("PackageDependencies", StringComparison.OrdinalIgnoreCase))
                                {
                                    var projectEvaluation = GetNearestProjectEvaluation(node);
                                    if (projectEvaluation is not null)
                                    {
                                        var specificPackageDeps = packageDependencies.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));
                                        var tfm = GetPropertyValueFromProjectEvaluation(projectEvaluation, "TargetFramework");
                                        if (tfm is not null)
                                        {
                                            var packagesByTfm = specificPackageDeps.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));
                                            foreach (var package in addItem.Children.OfType<Item>())
                                            {
                                                if (!NonReportedPackgeNames.Contains(package.Name))
                                                {
                                                    packagesByTfm.Add(package.Name);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            break;
                        case Target target when target.Name == "_HandlePackageFileConflicts":
                            // this only works if we've installed the exact SDK required
                            if (experimentsManager.InstallDotnetSdks)
                            {
                                var projectEvaluation = GetNearestProjectEvaluation(target);
                                if (projectEvaluation is null)
                                {
                                    break;
                                }

                                var removedReferences = target.Children.OfType<RemoveItem>().FirstOrDefault(r => r.Name == "Reference");
                                var addedReferences = target.Children.OfType<AddItem>().FirstOrDefault(r => r.Name == "Reference");
                                if (removedReferences is null || addedReferences is null)
                                {
                                    break;
                                }

                                foreach (var removedAssembly in removedReferences.Children.OfType<Item>())
                                {
                                    var removedPackageName = GetChildMetadataValue(removedAssembly, "NuGetPackageId");
                                    var removedFileName = Path.GetFileName(removedAssembly.Name);
                                    if (removedPackageName is null || removedFileName is null)
                                    {
                                        continue;
                                    }

                                    var existingProjectPackagesByTfm = packagesPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(PathComparer.Instance));
                                    var existingProjectPackages = existingProjectPackagesByTfm.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));
                                    if (!existingProjectPackages.ContainsKey(removedPackageName))
                                    {
                                        continue;
                                    }

                                    var correspondingAddedFile = addedReferences.Children.OfType<Item>()
                                        .FirstOrDefault(i => removedFileName.Equals(Path.GetFileName(i.Name), StringComparison.OrdinalIgnoreCase));
                                    if (correspondingAddedFile is null)
                                    {
                                        continue;
                                    }

                                    var runtimePackageName = GetChildMetadataValue(correspondingAddedFile, "NuGetPackageId");
                                    var runtimePackageVersion = GetChildMetadataValue(correspondingAddedFile, "NuGetPackageVersion");
                                    if (runtimePackageName is null ||
                                        runtimePackageVersion is null ||
                                        !SemVersion.TryParse(runtimePackageVersion, out var parsedRuntimePackageVersion))
                                    {
                                        continue;
                                    }

                                    var packageMapper = DotNetPackageCorrelationManager.GetPackageMapper();
                                    var replacementPackageVersion = packageMapper.GetPackageVersionThatShippedWithOtherPackage(runtimePackageName, parsedRuntimePackageVersion, removedPackageName);
                                    if (replacementPackageVersion is null)
                                    {
                                        continue;
                                    }

                                    var packagesPerThisProject = packagesReplacedBySdkPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(PathComparer.Instance));
                                    var packagesPerTfm = packagesPerThisProject.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));
                                    packagesPerTfm[removedPackageName] = replacementPackageVersion.ToString();
                                    var relativeProjectPath = Path.GetRelativePath(repoRootPath, projectEvaluation.ProjectFile).NormalizePathToUnix();
                                    logger.Info($"Re-added SDK managed package [{removedPackageName}/{replacementPackageVersion}] to project [{relativeProjectPath}]");
                                }
                            }
                            break;
                    }
                }, takeChildrenSnapshot: true);
            }
            catch (HttpRequestException)
            {
                // likely an unauthenticated feed; this needs to be sent further up the chain
                throw;
            }
            finally
            {
                try
                {
                    File.Delete(binLogPath);
                }
                catch
                {
                }
            }
        }

        if (requiresManualPackageResolution)
        {
            // we were able to collect all <PackageReference> elements, but no transitive dependencies were resolved
            // to do this we create a temporary project with all of the top-level project elements, resolve _again_, then rebuild the proper result
            packagesPerProject = await RebuildPackagesPerProject(
                repoRootPath,
                startingProjectPath,
                tfms,
                packagesPerProject,
                explicitPackageVersionsPerProject,
                experimentsManager,
                logger
            );
        }

        // and done
        var projectDiscoveryResults = await BuildResults(
            repoRootPath,
            workspacePath,
            packagesPerProject,
            explicitPackageVersionsPerProject,
            packagesReplacedBySdkPerProject,
            topLevelPackagesPerProject,
            resolvedProperties,
            packageDependencies,
            referencedProjects,
            importedFiles,
            additionalFiles
        );
        return projectDiscoveryResults;
    }

    private static async Task<ImmutableArray<ProjectDiscoveryResult>> BuildResults(
        string repoRootPath,
        string workspacePath,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesPerProject,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packageVersionsPerProject,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesReplacedBySdkPerProject,
        Dictionary<string, Dictionary<string, HashSet<string>>> topLevelPackagesPerProject,
        Dictionary<string, Dictionary<string, string>> resolvedProperties,
        Dictionary<string, Dictionary<string, HashSet<string>>> packageDependencies,
        Dictionary<string, HashSet<string>> referencedProjects,
        Dictionary<string, HashSet<string>> importedFiles,
        Dictionary<string, HashSet<string>> additionalFiles
    )
    {
        var projectDiscoveryResults = new List<ProjectDiscoveryResult>();
        foreach (var projectPath in packagesPerProject.Keys.OrderBy(p => p))
        {
            // gather some project-level information
            var packagesByTfm = packagesPerProject[projectPath];
            if (packagesReplacedBySdkPerProject.TryGetValue(projectPath, out var packagesReplacedBySdk))
            {
                var consolidatedPackagesByTfm = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);

                // copy the first dictionary
                foreach (var kvp in packagesByTfm)
                {
                    var tfm = kvp.Key;
                    var packages = kvp.Value;
                    consolidatedPackagesByTfm[tfm] = packages;
                }

                // merge in the second
                foreach (var kvp in packagesReplacedBySdk)
                {
                    var tfm = kvp.Key;
                    var packages = kvp.Value;
                    var replacedPackages = consolidatedPackagesByTfm.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));
                    foreach (var packagePair in packages)
                    {
                        replacedPackages[packagePair.Key] = packagePair.Value;
                    }
                }

                packagesByTfm = consolidatedPackagesByTfm;
            }

            var projectFullDirectory = Path.GetDirectoryName(projectPath)!;
            var doc = XDocument.Load(projectPath);
            var localPropertyDefinitionElements = doc.Root!.XPathSelectElements("/Project/PropertyGroup/*");
            var projectPropertyNames = localPropertyDefinitionElements.Select(e => e.Name.LocalName).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var projectRelativePath = Path.GetRelativePath(workspacePath, projectPath);
            var topLevelPackageNames = topLevelPackagesPerProject
                .GetOrAdd(projectPath, () => new(StringComparer.OrdinalIgnoreCase))
                .SelectMany(kvp => kvp.Value)
                .ToHashSet(StringComparer.OrdinalIgnoreCase);

            var propertiesForProject = resolvedProperties.GetOrAdd(projectPath, () => new(StringComparer.OrdinalIgnoreCase));
            var assetsJson = new Lazy<JsonElement?>(() =>
            {
                if (propertiesForProject.TryGetValue("ProjectAssetsFile", out var assetsFilePath))
                {
                    var assetsContent = File.ReadAllText(assetsFilePath);
                    var assets = JsonDocument.Parse(assetsContent).RootElement;
                    return assets;
                }

                return null;
            });

            // create dependencies
            var tfms = packagesByTfm.Keys.OrderBy(tfm => tfm).ToImmutableArray();
            var groupedDependencies = new Dictionary<string, Dependency>(StringComparer.OrdinalIgnoreCase);
            foreach (var tfm in tfms)
            {
                var parsedTfm = NuGetFramework.Parse(tfm);
                var packages = packagesByTfm[tfm];

                // augment with any packages that might not have reported assemblies
                var assetsPackageVersions = new Lazy<Dictionary<string, string>>(() =>
                {
                    var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    if (assetsJson.Value is { } assets &&
                        assets.TryGetProperty("targets", out var tfmObjects))
                    {
                        foreach (var tfmObject in tfmObjects.EnumerateObject())
                        {
                            // TFM might have a RID suffix after a slash that we can't parse
                            var tfmParts = tfmObject.Name.Split('/');
                            var reportedTargetFramework = NuGetFramework.Parse(tfmParts[0]);
                            if (reportedTargetFramework == parsedTfm)
                            {
                                foreach (var packageObject in tfmObject.Value.EnumerateObject())
                                {
                                    var parts = packageObject.Name.Split('/');
                                    if (parts.Length == 2)
                                    {
                                        var packageName = parts[0];
                                        var packageVersion = parts[1];
                                        result[packageName] = packageVersion;
                                    }
                                }
                            }
                        }
                    }

                    return result;
                });
                var packageDepsForProject = packageDependencies.GetOrAdd(projectPath, () => new(StringComparer.OrdinalIgnoreCase));
                var packageDepsForTfm = packageDepsForProject.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));
                foreach (var packageDepName in packageDepsForTfm)
                {
                    if (packages.ContainsKey(packageDepName))
                    {
                        // we already know about this
                        continue;
                    }

                    // otherwise find the corresponding version through project.assets.json
                    if (assetsPackageVersions.Value.TryGetValue(packageDepName, out var packageDepVersion))
                    {
                        packages[packageDepName] = packageDepVersion;
                    }
                }

                foreach (var package in packages)
                {
                    var packageName = package.Key;
                    var packageVersion = package.Value;
                    var isTopLevel = topLevelPackageNames.Contains(packageName);
                    var dependencyType = isTopLevel ? DependencyType.PackageReference : DependencyType.Unknown;
                    var combinedTfms = new HashSet<string>([tfm], StringComparer.OrdinalIgnoreCase);
                    if (groupedDependencies.TryGetValue(packageName, out var existingDependency) &&
                        existingDependency.Version == packageVersion &&
                        existingDependency.Type == dependencyType &&
                        existingDependency.TargetFrameworks is not null)
                    {
                        // same dependency, combine tfms
                        combinedTfms.AddRange(existingDependency.TargetFrameworks);
                    }

                    var normalizedTfms = combinedTfms.OrderBy(t => t).ToImmutableArray();
                    groupedDependencies[package.Key] = new Dependency(packageName, packageVersion, dependencyType, TargetFrameworks: normalizedTfms, IsDirect: isTopLevel, IsTransitive: !isTopLevel);
                }
            }

            var dependencies = groupedDependencies.Values
                .OrderBy(d => d.Name)
                .ThenBy(d => d.Version)
                .ToImmutableArray();

            // others
            var projectProperties = resolvedProperties[projectPath];
            var properties = projectProperties
                .Where(pkvp => projectPropertyNames.Contains(pkvp.Key))
                .Select(pkvp => new Property(pkvp.Key, pkvp.Value, Path.GetRelativePath(repoRootPath, projectPath).NormalizePathToUnix()))
                .OrderBy(p => p.Name)
                .ToImmutableArray();
            var referenced = referencedProjects.GetOrAdd(projectPath, () => new(PathComparer.Instance))
                .Select(p => Path.GetRelativePath(projectFullDirectory, p).NormalizePathToUnix())
                .OrderBy(p => p)
                .ToImmutableArray();
            var imported = importedFiles.GetOrAdd(projectPath, () => new(PathComparer.Instance))
                .Select(p => Path.GetRelativePath(projectFullDirectory, p))
                .Select(p => p.NormalizePathToUnix())
                .OrderBy(p => p)
                .ToImmutableArray();
            var additionalFromLocation = ProjectHelper.GetAdditionalFilesFromProjectLocation(projectPath, ProjectHelper.PathFormat.Full);
            var additional = additionalFiles.GetOrAdd(projectPath, () => new(PathComparer.Instance))
                .Concat(additionalFromLocation)
                .Select(p => Path.GetRelativePath(projectFullDirectory, p))
                .Select(p => p.NormalizePathToUnix())
                .OrderBy(p => p)
                .ToImmutableArray();
            var useCpmTransitivePinning =
                projectProperties.TryGetValue("ManagePackageVersionsCentrally", out var useCpmString) &&
                bool.TryParse(useCpmString, out var useCpm) &&
                useCpm &&
                projectProperties.TryGetValue("CentralPackageTransitivePinningEnabled", out var useTransitivePinningString) &&
                bool.TryParse(useTransitivePinningString, out var useTransitivePinning) &&
                useTransitivePinning;

            var projectDiscoveryResult = new ProjectDiscoveryResult()
            {
                FilePath = projectRelativePath,
                Dependencies = dependencies,
                TargetFrameworks = tfms,
                Properties = properties,
                ReferencedProjectPaths = referenced,
                ImportedFiles = imported,
                AdditionalFiles = additional,
                CentralPackageTransitivePinningEnabled = useCpmTransitivePinning,
            };
            projectDiscoveryResults.Add(projectDiscoveryResult);
        }
        return projectDiscoveryResults.ToImmutableArray();
    }

    private static async Task<Dictionary<string, Dictionary<string, Dictionary<string, string>>>> RebuildPackagesPerProject(
        string repoRootPath,
        string projectPath,
        ImmutableArray<string> targetFrameworks,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesPerProject,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> explicitPackageVersionsPerProject,
        ExperimentsManager experimentsManager,
        ILogger logger
    )
    {
        var tempDirectory = Directory.CreateTempSubdirectory("legacy-package-reference-resolution_");
        try
        {
            // gather top level dependencies from topLevelPackagesPerProject
            // TODO: we don't currently partition dependencies by TFM; this will have to be redone when that's supported
            var topLevelDependencies = explicitPackageVersionsPerProject
                .GetOrAdd(projectPath, () => new(StringComparer.OrdinalIgnoreCase))
                .SelectMany(kvp => kvp.Value)
                .Select(kvp => new Dependency(kvp.Key, kvp.Value, DependencyType.PackageReference, TargetFrameworks: targetFrameworks))
                .ToImmutableArray();

            var tempProjectPath = await MSBuildHelper.CreateTempProjectAsync(tempDirectory, repoRootPath, projectPath, targetFrameworks, topLevelDependencies, experimentsManager, logger);
            var tempProjectDirectory = Path.GetDirectoryName(tempProjectPath)!;
            var rediscoveredDependencies = await DiscoverAsync(tempProjectDirectory, tempProjectDirectory, tempProjectPath, experimentsManager, logger);
            var rediscoveredDependenciesForThisProject = rediscoveredDependencies.Single(); // we started with a single temp project, this will be the only result

            // re-build packagesPerProject
            var rebuiltPackagesPerProject = packagesPerProject.ToDictionary(PathComparer.Instance); // shallow copy
            rebuiltPackagesPerProject[projectPath] = new(StringComparer.OrdinalIgnoreCase); // rebuild for this project
            var rebuiltPackagesForThisProject = rebuiltPackagesPerProject[projectPath];
            foreach (var tfm in targetFrameworks)
            {
                rebuiltPackagesForThisProject[tfm] = rediscoveredDependenciesForThisProject.Dependencies.ToDictionary(d => d.Name, d => d.Version!, StringComparer.OrdinalIgnoreCase);
            }

            return rebuiltPackagesPerProject;
        }
        finally
        {
            try
            {
                tempDirectory.Delete(recursive: true);
            }
            catch
            {
            }
        }
    }

    private static void ProcessResolvedPackageReference(
        NamedNode node,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesPerProject, // projectPath -> tfm -> (packageName, packageVersion)
        Dictionary<string, Dictionary<string, HashSet<string>>> topLevelPackagesPerProject, // projectPath -> tfm -> packageName
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packageVersionsPerProject, // projectPath -> tfm -> (packageName, packageVersion)
        ExperimentsManager experimentsManager
    )
    {
        var doRemoveOperation = node is RemoveItem;
        var doAddOperation = node is AddItem;

        if (TopLevelPackageItemNames.Contains(node.Name))
        {
            foreach (var child in node.Children.OfType<Item>())
            {
                var projectEvaluation = GetNearestProjectEvaluation(node);
                if (projectEvaluation is not null)
                {
                    var packageName = child.Name;
                    if (NonReportedPackgeNames.Contains(packageName))
                    {
                        continue;
                    }

                    var tfm = GetPropertyValueFromProjectEvaluation(projectEvaluation, "TargetFramework");
                    if (tfm is not null)
                    {
                        var topLevelPackages = topLevelPackagesPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));
                        var topLevelPackagesPerTfm = topLevelPackages.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));

                        if (doRemoveOperation)
                        {
                            topLevelPackagesPerTfm.Remove(packageName);
                        }

                        if (doAddOperation)
                        {
                            topLevelPackagesPerTfm.Add(packageName);
                            var packageVersion = GetChildMetadataValue(child, "Version");
                            if (packageVersion is not null)
                            {
                                var packagesPerTfm = packageVersionsPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));
                                var packageVersions = packagesPerTfm.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));
                                packageVersions[packageName] = packageVersion;
                            }
                        }
                    }
                }
            }
        }
        else if (ResolvedPackageItemNames.TryGetValue(node.Name, out var metadataNames))
        {
            var nameMetadata = metadataNames.NameMetadata;
            var versionMetadata = metadataNames.VersionMetadata;
            var projectEvaluation = GetNearestProjectEvaluation(node);
            if (projectEvaluation is not null)
            {
                // without a tfm we can't do anything meaningful with the package reference
                var tfm = GetPropertyValueFromProjectEvaluation(projectEvaluation, "TargetFramework");
                if (tfm is not null)
                {
                    foreach (var child in node.Children.OfType<Item>())
                    {
                        var packageName = GetChildMetadataValue(child, nameMetadata);
                        var packageVersion = GetChildMetadataValue(child, versionMetadata);
                        if (packageName is not null && packageVersion is not null)
                        {
                            if (NonReportedPackgeNames.Contains(packageName))
                            {
                                continue;
                            }

                            var tfmsPerProject = packagesPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));
                            var packagesPerTfm = tfmsPerProject.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));

                            if (doRemoveOperation)
                            {
                                packagesPerTfm.Remove(packageName);
                            }

                            if (doAddOperation)
                            {
                                packagesPerTfm[packageName] = packageVersion;
                            }
                        }
                    }
                }
            }
        }
        else if (PackageVersionItemNames.Contains(node.Name))
        {
            foreach (var child in node.Children.OfType<Item>())
            {
                var projectEvaluation = GetNearestProjectEvaluation(node);
                if (projectEvaluation is not null)
                {
                    var tfm = GetPropertyValueFromProjectEvaluation(projectEvaluation, "TargetFramework");
                    if (tfm is not null)
                    {
                        var packageName = child.Name;
                        var packageVersions = packageVersionsPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));
                        var packageVersionsPerTfm = packageVersions.GetOrAdd(tfm, () => new(StringComparer.OrdinalIgnoreCase));

                        if (doRemoveOperation)
                        {
                            packageVersionsPerTfm.Remove(packageName);
                        }

                        if (doAddOperation)
                        {
                            var packageVersion = GetChildMetadataValue(child, "Version");
                            if (packageVersion is not null)
                            {
                                packageVersionsPerTfm[packageName] = packageVersion;
                            }
                        }
                    }
                }
            }
        }
    }

    private static string? GetChildMetadataValue(TreeNode node, string metadataItemName)
    {
        var metadata = node.Children.OfType<Metadata>();
        var metadataValue = metadata.FirstOrDefault(m => m.Name.Equals(metadataItemName, StringComparison.OrdinalIgnoreCase))?.Value;
        return metadataValue;
    }

    private static ProjectEvaluation? GetNearestProjectEvaluation(BaseNode node)
    {
        // we need to find the containing project evaluation
        //   if this is a <PackageReference>, one of the parents is it
        //   otherwise, we need to find the parent `Project` and the corresponding evaluation from the build
        var projectEvaluation = node.GetNearestParent<ProjectEvaluation>();
        if (projectEvaluation is null)
        {
            var project = node.GetNearestParent<Project>();
            if (project is null)
            {
                return null;
            }

            var build = project.GetNearestParent<Build>();
            if (build is null)
            {
                return null;
            }

            projectEvaluation = build.FindEvaluation(project.EvaluationId);
        }

        if (!File.Exists(projectEvaluation?.ProjectFile))
        {
            // WPF creates temporary projects during evaluation that no longer exist on disk for analysis, but they're not necessary for our purposes.
            return null;
        }

        return projectEvaluation;
    }

    private static string? GetPropertyValueFromProjectEvaluation(ProjectEvaluation projectEvaluation, string propertyName)
    {
        var propertiesFolder = projectEvaluation.Children.OfType<Folder>().FirstOrDefault(f => f.Name == "Properties");
        if (propertiesFolder is null)
        {
            return null;
        }

        var property = propertiesFolder.Children.OfType<LoggerProperty>().FirstOrDefault(p => p.Name.Equals(propertyName, StringComparison.OrdinalIgnoreCase));
        if (property is null)
        {
            return null;
        }

        return property.Value;
    }
}
