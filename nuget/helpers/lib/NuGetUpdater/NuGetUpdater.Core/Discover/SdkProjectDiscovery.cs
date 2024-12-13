using System.Collections.Immutable;
using System.Reflection;
using System.Xml.Linq;
using System.Xml.XPath;

using Microsoft.Build.Logging.StructuredLogger;

using NuGet.Versioning;

using NuGetUpdater.Core.Utilities;

using LoggerProperty = Microsoft.Build.Logging.StructuredLogger.Property;

namespace NuGetUpdater.Core.Discover;

internal static class SdkProjectDiscovery
{
    private static readonly HashSet<string> TopLevelPackageItemNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        "PackageReference"
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
        if (experimentsManager.UseDirectDiscovery)
        {
            return await DiscoverWithBinLogAsync(repoRootPath, workspacePath, startingProjectPath, logger);
        }
        else
        {
            return await DiscoverWithTempProjectAsync(repoRootPath, workspacePath, startingProjectPath, logger);
        }
    }

    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverWithBinLogAsync(string repoRootPath, string workspacePath, string startingProjectPath, ILogger logger)
    {
        // N.b., there are many paths used in this function.  The MSBuild binary log always reports fully qualified paths, so that's what will be used
        // throughout until the very end when the appropriate kind of relative path is returned.

        // step through the binlog one item at a time
        var startingProjectDirectory = Path.GetDirectoryName(startingProjectPath)!;

        // the following collection feature heavily; the shape is described as follows

        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesPerProject = new(PathComparer.Instance);
        //         projectPath        tfm           packageName, packageVersion

        Dictionary<string, HashSet<string>> topLevelPackagesPerProject = new(PathComparer.Instance);
        //         projectPath, packageNames

        Dictionary<string, Dictionary<string, string>> resolvedProperties = new(PathComparer.Instance);
        //         projectPath        propertyName, propertyValue

        Dictionary<string, HashSet<string>> importedFiles = new(PathComparer.Instance);
        //         projectPath, importedFiles

        Dictionary<string, HashSet<string>> referencedProjects = new(PathComparer.Instance);
        //         projectPath, referencedProjects

        Dictionary<string, HashSet<string>> additionalFiles = new(PathComparer.Instance);
        //         projectPath, additionalFiles

        var tfms = await MSBuildHelper.GetTargetFrameworkValuesFromProject(repoRootPath, startingProjectPath, logger);
        foreach (var tfm in tfms)
        {
            // create a binlog
            var binLogPath = Path.Combine(Path.GetTempPath(), $"msbuild_{Guid.NewGuid():d}.binlog");
            try
            {
                // TODO: once the updater image has all relevant SDKs installed, we won't have to sideline global.json anymore
                var (exitCode, stdOut, stdErr) = await MSBuildHelper.SidelineGlobalJsonAsync(startingProjectDirectory, repoRootPath, async () =>
                {
                    // the built-in target `GenerateBuildDependencyFile` forces resolution of all NuGet packages, but doesn't invoke a full build
                    var dependencyDiscoveryTargetsPath = Path.Combine(Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!, "DependencyDiscovery.targets");
                    var args = new string[]
                    {
                        "build",
                        startingProjectPath,
                        "/t:_DiscoverDependencies",
                        $"/p:TargetFramework={tfm}",
                        $"/p:CustomAfterMicrosoftCommonCrossTargetingTargets={dependencyDiscoveryTargetsPath};CustomAfterMicrosoftCommonTargets={dependencyDiscoveryTargetsPath}",
                        $"/bl:{binLogPath}"
                    };
                    var (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", args, workingDirectory: startingProjectDirectory);
                    return (exitCode, stdOut, stdErr);
                }, logger, retainMSBuildSdks: true);
                MSBuildHelper.ThrowOnUnauthenticatedFeed(stdOut);
                if (stdOut.Contains("""error MSB4057: The target "GenerateBuildDependencyFile" does not exist in the project."""))
                {
                    // this can happen if it's a non-SDK-style project; totally normal, not worth examining the binlog
                    return [];
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
                            ProcessResolvedPackageReference(namedNode, packagesPerProject, topLevelPackagesPerProject);

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

        // and done
        var projectDiscoveryResults = packagesPerProject.Keys.OrderBy(p => p).Select(projectPath =>
        {
            // gather some project-level information
            var packagesByTfm = packagesPerProject[projectPath];
            var projectFullDirectory = Path.GetDirectoryName(projectPath)!;
            var doc = XDocument.Load(projectPath);
            var localPropertyDefinitionElements = doc.Root!.XPathSelectElements("/Project/PropertyGroup/*");
            var projectPropertyNames = localPropertyDefinitionElements.Select(e => e.Name.LocalName).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var projectRelativePath = Path.GetRelativePath(workspacePath, projectPath);
            var topLevelPackageNames = topLevelPackagesPerProject.GetOrAdd(projectPath, () => new(StringComparer.OrdinalIgnoreCase));

            // create dependencies
            var tfms = packagesByTfm.Keys.OrderBy(tfm => tfm).ToImmutableArray();
            var dependencies = tfms.SelectMany(tfm =>
            {
                return packagesByTfm[tfm].Keys.OrderBy(p => p).Select(packageName =>
                {
                    var packageVersion = packagesByTfm[tfm][packageName]!;
                    var isTopLevel = topLevelPackageNames.Contains(packageName);
                    var dependencyType = isTopLevel ? DependencyType.PackageReference : DependencyType.Unknown;
                    return new Dependency(packageName, packageVersion, dependencyType, TargetFrameworks: [tfm], IsDirect: isTopLevel, IsTransitive: !isTopLevel);
                });
            }).ToImmutableArray();

            // others
            var properties = resolvedProperties[projectPath]
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

            return new ProjectDiscoveryResult()
            {
                FilePath = projectRelativePath,
                Dependencies = dependencies,
                TargetFrameworks = tfms,
                Properties = properties,
                ReferencedProjectPaths = referenced,
                ImportedFiles = imported,
                AdditionalFiles = additional,
            };
        }).ToImmutableArray();
        return projectDiscoveryResults;
    }

    private static void ProcessResolvedPackageReference(
        NamedNode node,
        Dictionary<string, Dictionary<string, Dictionary<string, string>>> packagesPerProject, // projectPath -> tfm -> (packageName, packageVersion)
        Dictionary<string, HashSet<string>> topLevelPackagesPerProject
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

                    var topLevelPackages = topLevelPackagesPerProject.GetOrAdd(projectEvaluation.ProjectFile, () => new(StringComparer.OrdinalIgnoreCase));

                    if (doRemoveOperation)
                    {
                        topLevelPackages.Remove(packageName);
                    }

                    if (doAddOperation)
                    {
                        topLevelPackages.Add(packageName);
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

    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverWithTempProjectAsync(string repoRootPath, string workspacePath, string projectPath, ILogger logger)
    {
        // Determine which targets and props files contribute to the build.
        var (buildFiles, projectTargetFrameworks) = await MSBuildHelper.LoadBuildFilesAndTargetFrameworksAsync(repoRootPath, projectPath);
        var tfms = projectTargetFrameworks.Order().ToImmutableArray();

        // Get all the dependencies which are directly referenced from the project file or indirectly referenced from
        // targets and props files.
        var topLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles);

        var results = ImmutableArray.CreateBuilder<ProjectDiscoveryResult>();
        if (tfms.Length > 0)
        {
            foreach (var buildFile in buildFiles)
            {
                // Only include build files that exist beneath the RepoRootPath.
                if (buildFile.IsOutsideBasePath)
                {
                    continue;
                }

                // The build file dependencies have the correct DependencyType and the TopLevelDependencies have the evaluated version.
                // Combine them to have the set of dependencies that are directly referenced from the build file.
                var fileDependencies = BuildFile.GetDependencies(buildFile).ToImmutableArray();

                // this is new-ish behavior; don't ever report this dependency because there's no meaningful way to update it
                fileDependencies = fileDependencies.Where(d => !d.Name.Equals("Microsoft.NET.Sdk", StringComparison.OrdinalIgnoreCase)).ToImmutableArray();

                var fileDependencyLookup = fileDependencies
                    .ToLookup(d => d.Name, StringComparer.OrdinalIgnoreCase);
                var sdkDependencies = fileDependencies
                    .Where(d => d.Type == DependencyType.MSBuildSdk)
                    .ToImmutableArray();
                var indirectDependencies = topLevelDependencies
                    .Where(d => !fileDependencyLookup.Contains(d.Name))
                    .ToImmutableArray();
                var directDependencies = topLevelDependencies
                    .Where(d => fileDependencyLookup.Contains(d.Name))
                    .SelectMany(d =>
                    {
                        var dependencies = fileDependencyLookup[d.Name];
                        return dependencies.Select(fileDependency => d with
                        {
                            Type = fileDependency.Type,
                            IsDirect = true
                        });
                    }).ToImmutableArray();

                if (buildFile.GetFileType() == ProjectBuildFileType.Project)
                {
                    // Collect information that is specific to the project file.
                    var properties = MSBuildHelper.GetProperties(buildFiles).Values
                        .Where(p => !p.SourceFilePath.StartsWith(".."))
                        .OrderBy(p => p.Name)
                        .ToImmutableArray();
                    var referencedProjectPaths = MSBuildHelper.GetProjectPathsFromProject(projectPath)
                        .Select(path => Path.GetRelativePath(workspacePath, path).NormalizePathToUnix())
                        .OrderBy(p => p)
                        .ToImmutableArray();

                    // Get the complete set of dependencies including transitive dependencies.
                    var dependencies = indirectDependencies.Concat(directDependencies).ToImmutableArray();
                    dependencies = dependencies
                        .Select(d => d with { TargetFrameworks = tfms })
                        .ToImmutableArray();
                    var transitiveDependencies = await GetTransitiveDependencies(repoRootPath, projectPath, tfms, dependencies, logger);
                    ImmutableArray<Dependency> allDependencies = dependencies.Concat(transitiveDependencies).Concat(sdkDependencies)
                        .OrderBy(d => d.Name)
                        .ToImmutableArray();

                    // for the temporary project, these directories correspond to $(OutputPath) and $(IntermediateOutputPath) and files from
                    // these directories should not be reported
                    var intermediateDirectories = new string[]
                    {
                        Path.Join(Path.GetDirectoryName(buildFile.Path), "bin"),
                        Path.Join(Path.GetDirectoryName(buildFile.Path), "obj"),
                    };
                    var projectDirectory = Path.GetDirectoryName(buildFile.Path)!;
                    var additionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(buildFile.Path, ProjectHelper.PathFormat.Relative);
                    results.Add(new()
                    {
                        FilePath = Path.GetRelativePath(workspacePath, buildFile.Path).NormalizePathToUnix(),
                        Properties = properties,
                        TargetFrameworks = tfms,
                        ReferencedProjectPaths = referencedProjectPaths,
                        Dependencies = allDependencies,
                        ImportedFiles = buildFiles.Where(b =>
                            {
                                var fileType = b.GetFileType();
                                return fileType == ProjectBuildFileType.Props || fileType == ProjectBuildFileType.Targets;
                            })
                            .Where(b => !intermediateDirectories.Any(i => PathHelper.IsFileUnderDirectory(new DirectoryInfo(i), new FileInfo(b.Path))))
                            .Select(b => Path.GetRelativePath(projectDirectory, b.Path).NormalizePathToUnix())
                            .ToImmutableArray(),
                        AdditionalFiles = additionalFiles,
                    });
                }
            }
        }

        return results.ToImmutable();
    }

    private static async Task<ImmutableArray<Dependency>> GetTransitiveDependencies(string repoRootPath, string projectPath, ImmutableArray<string> tfms, ImmutableArray<Dependency> directDependencies, ILogger logger)
    {
        Dictionary<string, Dependency> transitiveDependencies = new(StringComparer.OrdinalIgnoreCase);
        foreach (var tfm in tfms)
        {
            var tfmDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(repoRootPath, projectPath, tfm, directDependencies, logger);
            foreach (var dependency in tfmDependencies.Where(d => d.IsTransitive))
            {
                if (!transitiveDependencies.TryGetValue(dependency.Name, out var existingDependency))
                {
                    transitiveDependencies[dependency.Name] = dependency;
                    continue;
                }

                transitiveDependencies[dependency.Name] = existingDependency with
                {
                    // Revisit this logic. We may want to return each dependency instead of merging them.
                    Version = NuGetVersion.Parse(existingDependency.Version!) > NuGetVersion.Parse(dependency.Version!)
                        ? existingDependency.Version
                        : dependency.Version,
                    TargetFrameworks = existingDependency.TargetFrameworks is not null && dependency.TargetFrameworks is not null
                        ? existingDependency.TargetFrameworks.Value.AddRange(dependency.TargetFrameworks)
                        : existingDependency.TargetFrameworks ?? dependency.TargetFrameworks,
                };
            }
        }

        return [.. transitiveDependencies.Values];
    }
}
