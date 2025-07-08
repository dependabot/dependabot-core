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
        var projectDirectory = Path.GetDirectoryName(projectPath.FullName)!;

        // first try non-project updates
        var updatedDotNetToolsPath = await DotNetToolsJsonUpdater.UpdateDependencyAsync(
            repoContentsPath.FullName,
            projectDirectory,
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
            projectDirectory,
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

        // then try packages.config updates
        var additionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(projectPath.FullName, ProjectHelper.PathFormat.Full);
        var packagesConfigFullPath = additionalFiles.Where(p => Path.GetFileName(p).Equals(ProjectHelper.PackagesConfigFileName, StringComparison.OrdinalIgnoreCase)).FirstOrDefault();
        if (packagesConfigFullPath is not null)
        {
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
                .ToArray();
            updateOperations.AddRange(packagesConfigOperationsWithNormalizedPaths);
            if (packagesConfigOperationsWithNormalizedPaths.Any(o => o.DependencyName.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) && o.NewVersion == newDependencyVersion))
            {
                // if we updated what we wanted, we can't do a direct xml update
                return [.. updateOperations];
            }
        }

        // then try project updates
        var initialProjectDiscovery = await GetProjectDiscoveryResult(repoContentsPath, projectPath);
        if (initialProjectDiscovery is null)
        {
            _logger.Info($"Unable to find project discovery for project {projectPath}.");
            return [.. updateOperations];
        }

        var initialRequestedDependency = initialProjectDiscovery.Dependencies
            .FirstOrDefault(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
        if (initialRequestedDependency is null || initialRequestedDependency.Version is null)
        {
            _logger.Info($"Dependency {dependencyName} not found in initial project discovery.");
            return [.. updateOperations];
        }

        var initialDependencyVersion = NuGetVersion.Parse(initialRequestedDependency.Version);
        if (initialDependencyVersion >= newDependencyVersion)
        {
            _logger.Info($"Dependency {dependencyName} is already at version {initialDependencyVersion}, no update needed.");
            return [.. updateOperations];
        }

        var initialTopLevelDependencies = initialProjectDiscovery.Dependencies
            .Where(d => !d.IsTransitive)
            .ToImmutableArray();
        var newDependency = new Dependency(dependencyName, newDependencyVersion.ToString(), DependencyType.Unknown);
        var desiredDependencies = initialTopLevelDependencies.Any(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase))
            ? initialTopLevelDependencies.Select(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase) ? newDependency : d).ToImmutableArray()
            : initialTopLevelDependencies.Concat([newDependency]).ToImmutableArray();

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

            var updatedFiles = await TryPerformFileWritesAsync(repoContentsPath, projectPath, initialProjectDiscovery, resolvedDependencies.Value);
            if (updatedFiles.Length == 0)
            {
                _logger.Warn("Failed to write new dependency versions.");
                continue;
            }

            // this final call to discover has the benefit of also updating the lock file if it exists
            var finalProjectDiscovery = await GetProjectDiscoveryResult(repoContentsPath, projectPath);
            if (finalProjectDiscovery is null)
            {
                _logger.Warn($"Unable to find final project discovery for project {projectPath}.");
                continue;
            }

            var finalRequestedDependency = finalProjectDiscovery.Dependencies
                .FirstOrDefault(d => d.Name.Equals(dependencyName, StringComparison.OrdinalIgnoreCase));
            if (finalRequestedDependency is null || finalRequestedDependency.Version is null)
            {
                _logger.Warn($"Dependency {dependencyName} not found in final project discovery.");
                continue;
            }

            var resolvedVersion = NuGetVersion.Parse(finalRequestedDependency.Version);
            if (resolvedVersion != newDependencyVersion)
            {
                _logger.Warn($"Final dependency version for {dependencyName} is {resolvedVersion}, expected {newDependencyVersion}.");
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
                .Select(op => op with { UpdatedFiles = [.. updatedFiles] })
                .ToImmutableArray();
            updateOperations.AddRange(computedOperationsWithUpdatedFiles);
        }

        return [.. updateOperations];
    }

    private async Task<ImmutableArray<string>> TryPerformFileWritesAsync(DirectoryInfo repoContentsPath, FileInfo projectPath, ProjectDiscoveryResult projectDiscovery, ImmutableArray<Dependency> requiredPackageVersions)
    {
        // track original contents
        var relativeFilePaths = new List<string>() { Path.GetRelativePath(repoContentsPath.FullName, projectPath.FullName) };
        var originalFileContents = new Dictionary<string, string>();
        var projectContents = await File.ReadAllTextAsync(projectPath.FullName);
        originalFileContents[projectPath.FullName] = projectContents;

        foreach (var file in projectDiscovery.ImportedFiles.Concat(projectDiscovery.AdditionalFiles))
        {
            var filePath = Path.Join(Path.GetDirectoryName(projectPath.FullName), file).FullyNormalizedRootedPath();
            var fileContents = await File.ReadAllTextAsync(filePath);
            originalFileContents[filePath] = fileContents;
            relativeFilePaths.Add(Path.GetRelativePath(repoContentsPath.FullName, filePath));
        }

        // try update
        var success = await _fileWriter.UpdatePackageVersionsAsync(repoContentsPath, [.. relativeFilePaths], projectDiscovery.Dependencies, requiredPackageVersions);
        var updatedFiles = new List<string>();
        foreach (var (filePath, originalContents) in originalFileContents)
        {
            var currentContents = await File.ReadAllTextAsync(filePath);
            if (currentContents != originalContents)
            {
                var relativeUpdatedPath = Path.GetRelativePath(repoContentsPath.FullName, filePath).FullyNormalizedRootedPath();
                updatedFiles.Add(relativeUpdatedPath);
            }
        }

        if (!success)
        {
            // restore contents
            foreach (var (filePath, originalContents) in originalFileContents)
            {
                await File.WriteAllTextAsync(filePath, originalContents);
            }
        }

        var sortedUpdatedFiles = updatedFiles.OrderBy(p => p, StringComparer.Ordinal);
        return [.. sortedUpdatedFiles];
    }

    private async Task<ProjectDiscoveryResult?> GetProjectDiscoveryResult(DirectoryInfo repoContentsPath, FileInfo projectPath)
    {
        var relativeProjectPath = Path.GetRelativePath(repoContentsPath.FullName, projectPath.FullName).NormalizePathToUnix();
        var relativeProjectDirectory = Path.GetDirectoryName(relativeProjectPath)!;
        var initialDiscoveryResult = await _discoveryWorker.RunAsync(repoContentsPath.FullName, relativeProjectDirectory);
        var projectDiscovery = initialDiscoveryResult.Projects.FirstOrDefault(p => relativeProjectPath.Equals(Path.Join(initialDiscoveryResult.Path, p.FilePath).NormalizePathToUnix(), StringComparison.OrdinalIgnoreCase));
        return projectDiscovery;
    }
}
