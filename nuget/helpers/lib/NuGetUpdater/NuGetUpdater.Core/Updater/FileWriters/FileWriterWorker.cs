using System.Collections.Immutable;

using NuGet.Versioning;

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

        // then try packages.config updates
        var packagesConfigUpdates = await ProcessPackagesConfigUpdatesAsync(repoContentsPath, projectPath, dependencyName, oldDependencyVersion, newDependencyVersion);
        updateOperations.AddRange(packagesConfigUpdates);

        // then try project updates
        var packageReferenceUpdates = await ProcessPackageReferenceUpdatesAsync(repoContentsPath, initialProjectDirectory, projectPath, dependencyName, newDependencyVersion);
        updateOperations.AddRange(packageReferenceUpdates);

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
        var additionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(projectPath.FullName, ProjectHelper.PathFormat.Full);
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
            .Where(d => !d.IsTransitive)
            .ToImmutableArray();
        var newDependency = new Dependency(dependencyName, newDependencyVersion.ToString(), DependencyType.Unknown);
        var desiredDependencies = initialTopLevelDependencies.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
            ? initialTopLevelDependencies.Select(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) ? newDependency : d).ToImmutableArray()
            : initialTopLevelDependencies.Concat([newDependency]).ToImmutableArray();

        var updateOperations = new List<UpdateOperationBase>();
        foreach (var targetFramework in initialProjectDiscovery.TargetFrameworks)
        {
            var resolvedDependencies = await _dependencySolver.SolveAsync(initialTopLevelDependencies, desiredDependencies, targetFramework);
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
                var updatedFiles = await TryPerformFileWritesAsync(_fileWriter, repoContentsPath, initialProjectDirectory, projectDiscovery, resolvedDependencies.Value);
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

            var computedUpdateOperations = await PackageReferenceUpdater.ComputeUpdateOperations(
                repoContentsPath.FullName,
                projectPath.FullName,
                targetFramework,
                initialTopLevelDependencies,
                desiredDependencies,
                resolvedDependencies.Value,
                new ExperimentsManager() { UseDirectDiscovery = true },
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
        var addPackageReferenceElementForPinnedPackages = !projectDiscovery.CentralPackageTransitivePinningEnabled;
        var success = await fileWriter.UpdatePackageVersionsAsync(repoContentsPath, relativeFilePaths, projectDiscovery.Dependencies, requiredPackageVersions, addPackageReferenceElementForPinnedPackages);
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
