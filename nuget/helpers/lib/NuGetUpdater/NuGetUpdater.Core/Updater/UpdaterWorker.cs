using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.DependencySolver;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Updater.FileWriters;

namespace NuGetUpdater.Core;

public delegate IDependencySolver DependencySolverFactory(string workspacePath);

public class UpdaterWorker : IUpdaterWorker
{
    private readonly string _jobId;
    private readonly IDiscoveryWorker _discoveryWorker;
    private readonly DependencySolverFactory _dependencySolverFactory;
    private readonly ImmutableArray<IFileWriter> _fileWriters;
    private readonly ComputeUpdateOperations _computeUpdateOperations;
    private readonly ExperimentsManager _experimentsManager;
    private readonly ILogger _logger;

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(), new VersionConverter() },
    };

    public UpdaterWorker(
        string jobId,
        IDiscoveryWorker discoveryWorker,
        DependencySolverFactory dependencySolverFactory,
        IEnumerable<IFileWriter> fileWriters,
        ComputeUpdateOperations computeUpdateOperations,
        ExperimentsManager experimentsManager,
        ILogger logger
    )
    {
        _jobId = jobId;
        _discoveryWorker = discoveryWorker;
        _dependencySolverFactory = dependencySolverFactory;
        _fileWriters = [.. fileWriters];
        _computeUpdateOperations = computeUpdateOperations;
        _experimentsManager = experimentsManager;
        _logger = logger;
    }

    // this is a convenient method for tests
    internal async Task<UpdateOperationResult> RunWithErrorHandlingAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        try
        {
            var result = await RunAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
            return result;
        }
        catch (Exception ex)
        {
            if (!Path.IsPathRooted(workspacePath) || !File.Exists(workspacePath))
            {
                workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
            }

            var error = JobErrorBase.ErrorFromException(ex, _jobId, workspacePath);
            var result = new UpdateOperationResult()
            {
                UpdateOperations = [],
                Error = error,
            };
            return result;
        }
    }

    public async Task<UpdateOperationResult> RunAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive)
    {
        MSBuildHelper.RegisterMSBuild(Environment.CurrentDirectory, repoRootPath, _logger);

        if (!Path.IsPathRooted(workspacePath) || !File.Exists(workspacePath))
        {
            workspacePath = Path.GetFullPath(Path.Join(repoRootPath, workspacePath));
        }

        var dependencySolver = _dependencySolverFactory(workspacePath);
        var worker = new FileWriterWorker(_discoveryWorker, dependencySolver, _fileWriters, _computeUpdateOperations, _logger);
        var updateOperations = await worker.RunAsync(
            new DirectoryInfo(repoRootPath),
            new FileInfo(workspacePath),
            dependencyName,
            NuGetVersion.Parse(previousDependencyVersion),
            NuGetVersion.Parse(newDependencyVersion)
        );
        return new UpdateOperationResult()
        {
            UpdateOperations = updateOperations,
        };
    }

    internal static string Serialize(UpdateOperationResult result)
    {
        var resultJson = JsonSerializer.Serialize(result, SerializerOptions);
        return resultJson;
    }

    internal static async Task WriteResultFile(UpdateOperationResult result, string resultOutputPath, ILogger logger)
    {
        logger.Info($"  Writing update result to [{resultOutputPath}].");

        var resultJson = Serialize(result);
        await File.WriteAllTextAsync(resultOutputPath, resultJson);
    }
}
