using System.Collections.Immutable;

using NuGet.Frameworks;
using NuGet.Packaging.Core;
using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.DependencySolver;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Updater.FileWriters;

public class FileWriterWorker
{
    private readonly IDiscoveryWorker _discoveryWorker;
    private readonly IDependencySolver _dependencySolver;
    private readonly IFileWriter _fileWriter;
    private readonly ILogger _logger;

    public FileWriterWorker(IDiscoveryWorker discoveryWorker, IDependencySolver dependencySolver, IFileWriter fileWriter, ILogger logger)
    {
        _discoveryWorker = discoveryWorker;
        _dependencySolver = dependencySolver;
        _fileWriter = fileWriter;
        _logger = logger;
    }

    public async Task<ImmutableArray<UpdateOperationBase>> RunAsync(
        DirectoryInfo repoContentsPath,
        FileInfo projectPath,
        string dependencyName,
        NuGetVersion oldDependencyVersion,
        NuGetVersion newDependencyVersion
    )
    {
        var updateOperations = new List<UpdateOperationBase>();
        var initialProjectDirectory = new DirectoryInfo(Path.GetDirectoryName(projectPath.FullName)!);

        // first try non-project updates
        var nonProjectUpdates = await ProcessNonProjectUpdatesAsync(repoContentsPath, initialProjectDirectory, dependencyName, oldDependencyVersion, newDependencyVersion);
        updateOperations.AddRange(nonProjectUpdates);

        var projectExtension = projectPath.Extension.ToLowerInvariant();
        if (XmlFileWriter.SupportedProjectFileExtensions.Contains(projectExtension))
        {
            // then try packages.config updates
            var packagesConfigUpdates = await ProcessPackagesConfigUpdatesAsync(repoContentsPath, projectPath, dependencyName, oldDependencyVersion, newDependencyVersion);
            updateOperations.AddRange(packagesConfigUpdates);

            // then try project updates
            var packageReferenceUpdates = await ProcessPackageReferenceUpdatesAsync(repoContentsPath, initialProjectDirectory, projectPath, dependencyName, newDependencyVersion);
            updateOperations.AddRange(packageReferenceUpdates);
        }

        var normalizedUpdateOperations = UpdateOperationBase.NormalizeUpdateOperationCollection(repoContentsPath.FullName, updateOperations);
        return normalizedUpdateOperations;
    }

    private async Task<ImmutableArray<UpdateOperationBase>> ProcessNonProjectUpdatesAsync(
        DirectoryInfo repoContentsPath,
        DirectoryInfo initialProjectDirectory,
        string dependencyName,
        NuGetVersion oldDependencyVersion,
        NuGetVersion newDependencyVersion
    )
    {
        var updateOperations = new List<UpdateOperationBase>();
        var updatedDotNetToolsPath = await DotNetToolsJsonUpdater.UpdateDependencyAsync(
            repoContentsPath.FullName,
            initialProjectDirectory.FullName,
            dependencyName,
            oldDependencyVersion.ToString(),
            newDependencyVersion.ToString(),
            _logger
        );
        if (updatedDotNetToolsPath is not null)
        {
            updateOperations.Add(new DirectUpdate()
            {
                DependencyName = dependencyName,
                OldVersion = oldDependencyVersion,
                NewVersion = newDependencyVersion,
                UpdatedFiles = [Path.GetRelativePath(repoContentsPath.FullName, updatedDotNetToolsPath).FullyNormalizedRootedPath()]
            });
        }

        var updatedGlobalJsonPath = await GlobalJsonUpdater.UpdateDependencyAsync(
            repoContentsPath.FullName,
            initialProjectDirectory.FullName,
            dependencyName,
            oldDependencyVersion.ToString(),
            newDependencyVersion.ToString(),
            _logger
        );
        if (updatedGlobalJsonPath is not null)
        {
            updateOperations.Add(new DirectUpdate()
            {
                DependencyName = dependencyName,
                OldVersion = oldDependencyVersion,
                NewVersion = newDependencyVersion,
                UpdatedFiles = [Path.GetRelativePath(repoContentsPath.FullName, updatedGlobalJsonPath).FullyNormalizedRootedPath()]
            });
        }

        return [.. updateOperations];
    }

    private async Task<ImmutableArray<UpdateOperationBase>> ProcessPackagesConfigUpdatesAsync(
        DirectoryInfo repoContentsPath,
        FileInfo projectPath,
        string dependencyName,
        NuGetVersion oldDependencyVersion,
        NuGetVersion newDependencyVersion
    )
    {
        var additionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(repoContentsPath.FullName, projectPath.FullName, ProjectHelper.PathFormat.Full);
        var packagesConfigFullPath = additionalFiles.Where(p => Path.GetFileName(p).Equals(ProjectHelper.PackagesConfigFileName, StringComparison.OrdinalIgnoreCase)).FirstOrDefault();
        if (packagesConfigFullPath is null)
        {
            return [];
        }

        var packagesConfigOperations = await PackagesConfigUpdater.UpdateDependencyAsync(
            repoContentsPath.FullName,
            projectPath.FullName,
            dependencyName,
            oldDependencyVersion.ToString(),
            newDependencyVersion.ToString(),
            packagesConfigFullPath,
            _logger
        );
        var packagesConfigOperationsWithNormalizedPaths = packagesConfigOperations
            .Select(op => op with { UpdatedFiles = [.. op.UpdatedFiles.Select(f => Path.GetRelativePath(repoContentsPath.FullName, f).FullyNormalizedRootedPath())] })
            .ToImmutableArray();
        return packagesConfigOperationsWithNormalizedPaths;
    }

    private async Task<ImmutableArray<UpdateOperationBase>> ProcessPackageReferenceUpdatesAsync(
        DirectoryInfo repoContentsPath,
        DirectoryInfo initialProjectDirectory,
        FileInfo projectPath,
        string dependencyName,
        NuGetVersion newDependencyVersion
    )
    {
        var initialProjectDirectoryRelativeToRepoRoot = Path.GetRelativePath(repoContentsPath.FullName, initialProjectDirectory.FullName).FullyNormalizedRootedPath();
        var initialDiscoveryResult = await _discoveryWorker.RunAsync(repoContentsPath.FullName, initialProjectDirectoryRelativeToRepoRoot);
        var initialProjectDiscovery = initialDiscoveryResult.GetProjectDiscoveryFromFullPath(repoContentsPath, projectPath);
        if (initialProjectDiscovery is null)
        {
            _logger.Info($"Unable to find project discovery for project {projectPath}.");
            return [];
        }

        var initialRequestedDependency = initialProjectDiscovery.Dependencies
            .FirstOrDefault(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (initialRequestedDependency is null || initialRequestedDependency.Version is null)
        {
            _logger.Info($"Dependency {dependencyName} not found in initial project discovery.");
            return [];
        }

        var initialDependencyVersion = NuGetVersion.Parse(initialRequestedDependency.Version);
        if (initialDependencyVersion >= newDependencyVersion)
        {
            _logger.Info($"Dependency {dependencyName} is already at version {initialDependencyVersion}, no update needed.");
            return [];
        }

        var initialTopLevelDependencies = initialProjectDiscovery.Dependencies
            .Where(d => d.IsTopLevel)
            .ToImmutableArray();
        var newDependency = new Dependency(dependencyName, newDependencyVersion.ToString(), DependencyType.Unknown);
        var desiredDependencies = initialTopLevelDependencies.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
            ? initialTopLevelDependencies.Select(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) ? newDependency : d).ToImmutableArray()
            : initialTopLevelDependencies.Concat([newDependency]).ToImmutableArray();

        var updateOperations = new List<UpdateOperationBase>();
        foreach (var targetFramework in initialProjectDiscovery.TargetFrameworks)
        {
            var resolvedDependencies = await SolveForFrameworkAsync(initialProjectDiscovery, initialTopLevelDependencies, desiredDependencies, targetFramework);
            if (resolvedDependencies is null)
            {
                _logger.Warn($"Unable to solve dependency conflicts for target framework {targetFramework}.");
                continue;
            }

            var resolvedRequestedDependency = resolvedDependencies.Value
                .SingleOrDefault(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
            if (resolvedRequestedDependency is null || resolvedRequestedDependency.Version is null)
            {
                _logger.Warn($"Dependency resolution failed to include {dependencyName}.");
                continue;
            }

            var resolvedRequestedDependencyVersion = NuGetVersion.Parse(resolvedRequestedDependency.Version);
            if (resolvedRequestedDependencyVersion != newDependencyVersion)
            {
                _logger.Warn($"Requested dependency resolution to include {dependencyName}/{newDependencyVersion} but it was instead resolved to {resolvedRequestedDependencyVersion}.");
                continue;
            }

            // process all projects bottom up
            var orderedProjectDiscovery = GetProjectDiscoveryEvaluationOrder(repoContentsPath, initialDiscoveryResult, projectPath, _logger);

            // track original contents
            var originalFileContents = await GetOriginalFileContentsAsync(repoContentsPath, initialProjectDirectory, orderedProjectDiscovery);

            var allUpdatedFiles = new List<string>();
            foreach (var projectDiscovery in orderedProjectDiscovery)
            {
                var projectFullPath = Path.Join(repoContentsPath.FullName, initialDiscoveryResult.Path, projectDiscovery.FilePath).FullyNormalizedRootedPath();
                var projectDirectory = new DirectoryInfo(Path.GetDirectoryName(projectFullPath)!);
                var projectRelativePath = Path.GetRelativePath(repoContentsPath.FullName, projectFullPath).FullyNormalizedRootedPath();
                var projectRelativeDirectory = Path.GetDirectoryName(projectRelativePath)!.NormalizePathToUnix();
                _logger.Info($"Attempting to update {dependencyName} for {projectRelativePath}");

                // rerun discovery because a previous file update may have already fixed this
                var rerunWorkspaceDiscovery = await _discoveryWorker.RunAsync(repoContentsPath.FullName, projectRelativeDirectory);
                var rerunProjectDiscovery = rerunWorkspaceDiscovery.GetProjectDiscoveryFromFullPath(repoContentsPath, new FileInfo(projectFullPath));
                if (rerunProjectDiscovery is null)
                {
                    _logger.Warn($"  Unable to re-run project discovery for project {projectRelativePath}.");
                    continue;
                }

                var candidateDependencyToUpdate = rerunProjectDiscovery.Dependencies.FirstOrDefault(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
                if (candidateDependencyToUpdate?.Version is null)
                {
                    _logger.Warn($"  Unable to find dependency after discovery rerun.");
                    continue;
                }

                if (!NuGetVersion.TryParse(candidateDependencyToUpdate.Version, out var candidateDependencyCurrentVersion))
                {
                    _logger.Warn($"  Unable to parse discovered version number from string: {candidateDependencyToUpdate.Version}");
                    continue;
                }

                if (candidateDependencyCurrentVersion >= newDependencyVersion)
                {
                    _logger.Info($"  Dependency is already up to date at version {candidateDependencyCurrentVersion}, possibly from a previous operation.");
                    continue;
                }

                var rerunTopLevelDependencies = rerunProjectDiscovery.Dependencies
                    .Where(d => d.IsTopLevel)
                    .ToImmutableArray();
                var rerunDesiredDependencies = rerunTopLevelDependencies.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
                    ? rerunTopLevelDependencies.Select(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) ? newDependency : d).ToImmutableArray()
                    : rerunTopLevelDependencies.Concat([newDependency]).ToImmutableArray();
                var resolvedDependenciesByFramework = ImmutableDictionary.CreateBuilder<string, ImmutableArray<Dependency>>();
                var projectTargetFrameworks = candidateDependencyToUpdate.TargetFrameworks ?? rerunProjectDiscovery.TargetFrameworks;
                foreach (var projectTargetFramework in projectTargetFrameworks)
                {
                    var resolvedDependenciesInThisProject = await SolveForFrameworkAsync(
                        rerunProjectDiscovery, rerunTopLevelDependencies, rerunDesiredDependencies, projectTargetFramework);
                    if (resolvedDependenciesInThisProject is null ||
                        !resolvedDependenciesInThisProject.Value.Any(d =>
                            d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) &&
                            d.Version is not null && NuGetVersion.Parse(d.Version) == newDependencyVersion))
                    {
                        _logger.Warn($"  Unable to solve dependency conflicts for {projectRelativePath}/{projectTargetFramework}.");
                        resolvedDependenciesByFramework.Clear();
                        break;
                    }

                    resolvedDependenciesByFramework[projectTargetFramework] = resolvedDependenciesInThisProject.Value;
                }

                if (resolvedDependenciesByFramework.Count == 0)
                {
                    continue;
                }

                var resolvedProjectDependencies = resolvedDependenciesByFramework.ToImmutable().GetDependencies();
                if (!await IsMergedSolutionCompatibleAsync(rerunProjectDiscovery, repoContentsPath.FullName, projectFullPath, resolvedProjectDependencies))
                {
                    continue;
                }

                var updatedFiles = await TryPerformFileWritesAsync(_fileWriter, repoContentsPath, projectDirectory, rerunProjectDiscovery!, resolvedProjectDependencies);
                if (updatedFiles.Length == 0)
                {
                    _logger.Info("  Files were unable to be updated.");
                }
                else
                {
                    _logger.Info($"  Successfully updated the following files: {string.Join(", ", updatedFiles)}");
                }

                allUpdatedFiles.AddRange(updatedFiles);
            }

            if (allUpdatedFiles.Count == 0)
            {
                _logger.Warn("Failed to write new dependency versions.");
                await RestoreOriginalFileContentsAsync(originalFileContents);
                continue;
            }

            // this final call to discover has the benefit of also updating the lock file if it exists
            var finalDiscoveryResult = await _discoveryWorker.RunAsync(repoContentsPath.FullName, initialProjectDirectoryRelativeToRepoRoot);
            var finalProjectDiscovery = finalDiscoveryResult.GetProjectDiscoveryFromFullPath(repoContentsPath, projectPath);
            if (finalProjectDiscovery is null)
            {
                _logger.Warn($"Unable to find final project discovery for project {projectPath}.");
                await RestoreOriginalFileContentsAsync(originalFileContents);
                continue;
            }

            var finalRequestedDependency = finalProjectDiscovery.Dependencies
                .FirstOrDefault(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
            if (finalRequestedDependency is null || finalRequestedDependency.Version is null)
            {
                _logger.Warn($"Dependency {dependencyName} not found in final project discovery.");
                await RestoreOriginalFileContentsAsync(originalFileContents);
                continue;
            }

            var resolvedVersion = NuGetVersion.Parse(finalRequestedDependency.Version);
            if (resolvedVersion != newDependencyVersion)
            {
                _logger.Warn($"Final dependency version for {dependencyName} is {resolvedVersion}, expected {newDependencyVersion}.");
                await RestoreOriginalFileContentsAsync(originalFileContents);
                continue;
            }

            var finalResolvedDependencies = resolvedDependencies.Value
                .Concat(finalProjectDiscovery.Dependencies.Where(d => d.IsTopLevel))
                .DistinctBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
                .Select(d => d with
                {
                    Version = finalProjectDiscovery.Dependencies.FirstOrDefault(final => final.Name.Equals(d.Name, StringComparison.OrdinalIgnoreCase))?.Version ?? d.Version,
                })
                .ToImmutableArray();
            var computedUpdateOperations = PackageReferenceUpdater.ComputeUpdateOperations(
                initialTopLevelDependencies,
                desiredDependencies,
                finalResolvedDependencies,
                finalProjectDiscovery.DependencyGraph,
                _logger);
            var filteredUpdateOperations = computedUpdateOperations
                .Where(op =>
                {
                    var initialDependency = initialProjectDiscovery.Dependencies.FirstOrDefault(d => d.Name.Equals(op.DependencyName, StringComparison.OrdinalIgnoreCase));
                    return initialDependency is not null
                        && initialDependency.Version is not null
                        && NuGetVersion.Parse(initialDependency.Version) < op.NewVersion;
                })
                .ToImmutableArray();
            var computedOperationsWithUpdatedFiles = filteredUpdateOperations
                .Select(op => op with { UpdatedFiles = [.. allUpdatedFiles] })
                .ToImmutableArray();
            updateOperations.AddRange(computedOperationsWithUpdatedFiles);
        }

        return [.. updateOperations];
    }

    private Task<ImmutableArray<Dependency>?> SolveForFrameworkAsync(
        ProjectDiscoveryResult project,
        ImmutableArray<Dependency> existingDependencies,
        ImmutableArray<Dependency> desiredDependencies,
        string targetFramework)
    {
        var framework = project.GetFramework(targetFramework);
        return _dependencySolver.SolveAsync(
            FilterDependenciesForFramework(project, existingDependencies, framework),
            FilterDependenciesForFramework(project, desiredDependencies, framework),
            framework);
    }

    private static ImmutableArray<Dependency> FilterDependenciesForFramework(
        ProjectDiscoveryResult project,
        ImmutableArray<Dependency> dependencies,
        NuGetFramework framework)
    {
        bool IsApplicable(Dependency dependency)
        {
            var frameworks = dependency.TargetFrameworks ??
                project.Dependencies.FirstOrDefault(d => d.Name.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase))?.TargetFrameworks;
            return frameworks is null ||
                frameworks.Value.Any(tfm => NuGetFramework.Comparer.Equals(NuGetFramework.Parse(tfm), framework));
        }

        return dependencies.Where(IsApplicable).ToImmutableArray();
    }

    private async Task<bool> IsMergedSolutionCompatibleAsync(
        ProjectDiscoveryResult project,
        string repoRoot,
        string projectPath,
        ImmutableArray<Dependency> mergedDependencies)
    {
        if (project.TargetFrameworks.Length <= 1)
        {
            return true;
        }

        var usesTransitivePinning = project.PackageManagementKind == PackageManagementKind.CentralPackageManagementWithTransitivePinning;
        using var context = new NuGetContext(Path.GetDirectoryName(projectPath));
        foreach (var dependency in mergedDependencies)
        {
            var originalDependency = project.Dependencies.FirstOrDefault(d =>
                (d.IsTopLevel || usesTransitivePinning) && d.Name.Equals(dependency.Name, StringComparison.OrdinalIgnoreCase));
            if (originalDependency?.Version == dependency.Version)
            {
                continue;
            }

            var affectedFrameworks = (originalDependency?.TargetFrameworks ?? project.TargetFrameworks)
                .Select(project.GetFramework)
                .ToImmutableArray();
            if (!NuGetVersion.TryParse(dependency.Version, out var version) ||
                !await CompatibilityChecker.CheckAsync(new PackageIdentity(dependency.Name, version), affectedFrameworks, context, _logger, CancellationToken.None))
            {
                _logger.Warn($"  Merged dependency {dependency.Name}/{dependency.Version} is incompatible with the project's target frameworks.");
                return false;
            }
        }

        var topLevelDependencies = project.Dependencies.Where(d => d.IsTopLevel).ToImmutableArray();
        var topLevelNames = topLevelDependencies.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var candidateReferences = topLevelDependencies
            .Select(d => d with
            {
                Version = mergedDependencies.FirstOrDefault(merged => merged.Name.Equals(d.Name, StringComparison.OrdinalIgnoreCase))?.Version ?? d.Version,
            })
            .Concat(mergedDependencies.Where(d => !topLevelNames.Contains(d.Name))
                .Select(d => d with
                {
                    TargetFrameworks = usesTransitivePinning
                        ? project.Dependencies.FirstOrDefault(original => original.Name.Equals(d.Name, StringComparison.OrdinalIgnoreCase))?.TargetFrameworks ?? project.TargetFrameworks
                        : project.TargetFrameworks,
                }))
            .ToImmutableArray();
        foreach (var targetFramework in project.TargetFrameworks)
        {
            var framework = project.GetFramework(targetFramework);
            var references = FilterDependenciesForFramework(project, candidateReferences, framework);
            if (references.All(d => topLevelDependencies.Any(original =>
                original.Name.Equals(d.Name, StringComparison.OrdinalIgnoreCase) && original.Version == d.Version)))
            {
                continue;
            }

            var packageReferences = usesTransitivePinning
                ? references.Where(d => topLevelNames.Contains(d.Name)).ToImmutableArray()
                : references;
            ImmutableDictionary<string, string>? centralPackageVersions = null;
            ImmutableDictionary<string, string>? versionOverrides = null;
            if (usesTransitivePinning)
            {
                centralPackageVersions = project.GetCentralPackageVersions(targetFramework);
                versionOverrides = project.GetPackageReferenceVersionOverrides(targetFramework);
                if (centralPackageVersions is null || versionOverrides is null)
                {
                    _logger.Warn($"  Unable to validate central package versions for {targetFramework} without restored version information.");
                    return false;
                }

                var changedVersions = mergedDependencies
                    .Where(d => NuGetVersion.TryParse(d.Version, out var newVersion) &&
                        NuGetVersion.TryParse(project.Dependencies.FirstOrDefault(original => original.Name.Equals(d.Name, StringComparison.OrdinalIgnoreCase))?.Version, out var originalVersion) &&
                        newVersion != originalVersion)
                    .Select(d => KeyValuePair.Create(d.Name, d.Version!))
                    .ToArray();
                centralPackageVersions = centralPackageVersions.SetItems(changedVersions.Where(d => !versionOverrides.ContainsKey(d.Key)));
                versionOverrides = versionOverrides.SetItems(changedVersions.Where(d => versionOverrides.ContainsKey(d.Key)));
            }

            if (!await MSBuildHelper.IsPackageGraphCompatibleAsync(repoRoot, projectPath, framework, packageReferences, _logger,
                centralPackageVersions: centralPackageVersions,
                versionOverrides: versionOverrides))
            {
                return false;
            }
        }

        return true;
    }

    internal static async Task<Dictionary<string, string>> GetOriginalFileContentsAsync(DirectoryInfo repoContentsPath, DirectoryInfo initialStartingDirectory, IEnumerable<ProjectDiscoveryResult> projectDiscoveryResults)
    {
        var filesAndContents = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var projectDiscoveryResult in projectDiscoveryResults)
        {
            var fullProjectPath = Path.Join(initialStartingDirectory.FullName, projectDiscoveryResult.FilePath).FullyNormalizedRootedPath();
            var projectContents = await File.ReadAllTextAsync(fullProjectPath);
            filesAndContents[fullProjectPath] = projectContents;

            foreach (var file in projectDiscoveryResult.ImportedFiles.Concat(projectDiscoveryResult.AdditionalFiles))
            {
                var filePath = Path.Join(Path.GetDirectoryName(fullProjectPath)!, file).FullyNormalizedRootedPath();
                var fileContents = await File.ReadAllTextAsync(filePath);
                filesAndContents[filePath] = fileContents;
            }
        }

        return filesAndContents;
    }

    internal static async Task RestoreOriginalFileContentsAsync(Dictionary<string, string> originalFilesAndContents)
    {
        foreach (var (path, contents) in originalFilesAndContents)
        {
            await File.WriteAllTextAsync(path, contents);
        }
    }

    internal static ImmutableArray<ProjectDiscoveryResult> GetProjectDiscoveryEvaluationOrder(DirectoryInfo repoContentsPath, WorkspaceDiscoveryResult discoveryResult, FileInfo projectPath, ILogger logger)
    {
        var visitedProjectPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var projectsToProcess = new Queue<ProjectDiscoveryResult>();
        var startingProjectDiscovery = discoveryResult.GetProjectDiscoveryFromFullPath(repoContentsPath, projectPath);
        if (startingProjectDiscovery is null)
        {
            logger.Warn($"Unable to find project discovery for project {projectPath.FullName} in discovery result.");
            return [];
        }

        projectsToProcess.Enqueue(startingProjectDiscovery);

        var reversedProjectDiscoveryOrder = new List<ProjectDiscoveryResult>();
        while (projectsToProcess.TryDequeue(out var projectDiscovery))
        {
            var projectFullPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, projectDiscovery.FilePath).FullyNormalizedRootedPath();
            if (visitedProjectPaths.Add(projectFullPath))
            {
                reversedProjectDiscoveryOrder.Add(projectDiscovery);
                foreach (var referencedProjectPath in projectDiscovery.ReferencedProjectPaths)
                {
                    var referencedProjectFullPath = Path.Join(repoContentsPath.FullName, discoveryResult.Path, referencedProjectPath).FullyNormalizedRootedPath();
                    var referencedProjectDiscovery = discoveryResult.GetProjectDiscoveryFromFullPath(repoContentsPath, new FileInfo(referencedProjectFullPath));
                    if (referencedProjectDiscovery is not null)
                    {
                        projectsToProcess.Enqueue(referencedProjectDiscovery);
                    }
                }
            }
        }

        var projectDiscoveryOrder = ((IEnumerable<ProjectDiscoveryResult>)reversedProjectDiscoveryOrder)
            .Reverse()
            .ToImmutableArray();
        return projectDiscoveryOrder;
    }

    internal static async Task<ImmutableArray<string>> TryPerformFileWritesAsync(
        IFileWriter fileWriter,
        DirectoryInfo repoContentsPath,
        DirectoryInfo originalDiscoveryDirectory,
        ProjectDiscoveryResult projectDiscovery,
        ImmutableArray<Dependency> requiredPackageVersions
    )
    {
        var originalFileContents = await GetOriginalFileContentsAsync(repoContentsPath, originalDiscoveryDirectory, [projectDiscovery]);
        var relativeFilePaths = originalFileContents.Keys
            .Select(p => Path.GetRelativePath(repoContentsPath.FullName, p).FullyNormalizedRootedPath())
            .ToImmutableArray();

        // try update
        var success = await fileWriter.UpdatePackageVersionsAsync(repoContentsPath, relativeFilePaths, projectDiscovery.Dependencies, requiredPackageVersions, projectDiscovery.PackageManagementKind, projectDiscovery.PackageManagementSpecialFileRelativePath);
        var updatedFiles = new List<string>();
        foreach (var (filePath, originalContents) in originalFileContents)
        {
            var currentContents = await File.ReadAllTextAsync(filePath);
            var currentContentsNormalized = currentContents.Replace("\r", "");
            var originalContentsNormalized = originalContents.Replace("\r", "");
            if (currentContentsNormalized != originalContentsNormalized)
            {
                var relativeUpdatedPath = Path.GetRelativePath(repoContentsPath.FullName, filePath).FullyNormalizedRootedPath();
                updatedFiles.Add(relativeUpdatedPath);
            }
        }

        if (!success)
        {
            await RestoreOriginalFileContentsAsync(originalFileContents);
        }

        var sortedUpdatedFiles = updatedFiles.OrderBy(p => p, StringComparer.Ordinal).ToImmutableArray();
        return sortedUpdatedFiles;
    }
}
