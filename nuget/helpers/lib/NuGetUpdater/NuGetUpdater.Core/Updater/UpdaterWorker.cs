using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.DependencySolver;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Updater.FileWriters;

namespace NuGetUpdater.Core;

public class UpdaterWorker : IUpdaterWorker
{
    private readonly string _jobId;
    private readonly ExperimentsManager _experimentsManager;
    private readonly ILogger _logger;
    private readonly HashSet<string> _processedProjectPaths = new(StringComparer.OrdinalIgnoreCase);

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter(), new VersionConverter() },
    };

    public UpdaterWorker(string jobId, ExperimentsManager experimentsManager, ILogger logger)
    {
        _jobId = jobId;
        _experimentsManager = experimentsManager;
        _logger = logger;
    }

    public async Task RunAsync(string repoRootPath, string workspacePath, string dependencyName, string previousDependencyVersion, string newDependencyVersion, bool isTransitive, string? resultOutputPath = null)
    {
        var result = await RunWithErrorHandlingAsync(repoRootPath, workspacePath, dependencyName, previousDependencyVersion, newDependencyVersion, isTransitive);
        if (resultOutputPath is { })
        {
            await WriteResultFile(result, resultOutputPath, _logger);
        }
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

        var worker = new FileWriterWorker(
            new DiscoveryWorker(_jobId, _experimentsManager, _logger),
            new MSBuildDependencySolver(new DirectoryInfo(repoRootPath), new FileInfo(workspacePath), _logger),
            new XmlFileWriter(_logger),
            _logger
        );
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
