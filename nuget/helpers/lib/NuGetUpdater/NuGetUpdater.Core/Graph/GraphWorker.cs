using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Graph;

public class GraphWorker
{
    private readonly string _jobId;
    private readonly IApiHandler _apiHandler;
    private readonly IDiscoveryWorker _discoveryWorker;
    private readonly ILogger _logger;

    public GraphWorker(string jobId, IApiHandler apiHandler, IDiscoveryWorker discoveryWorker, ILogger logger)
    {
        _jobId = jobId;
        _apiHandler = apiHandler;
        _discoveryWorker = discoveryWorker;
        _logger = logger;
    }

    public async Task<int> RunAsync(FileInfo jobFilePath, DirectoryInfo repoContentsPath, string baseCommitSha)
    {
        var jobFileContent = await File.ReadAllTextAsync(jobFilePath.FullName);
        var jobWrapper = RunWorker.Deserialize(jobFileContent);
        var experimentsManager = ExperimentsManager.GetExperimentsManager(jobWrapper.Job.Experiments);
        return await RunAsync(jobWrapper.Job, repoContentsPath, baseCommitSha, experimentsManager);
    }

    public async Task<int> RunAsync(Job job, DirectoryInfo repoContentsPath, string baseCommitSha, ExperimentsManager experimentsManager)
    {
        var result = 0;
        JobErrorBase? error = null;

        try
        {
            var branch = job.Source.Branch ?? DetectDefaultBranch(repoContentsPath);
            var detectorVersion = GetDetectorVersion();
            var directories = job.GetAllDirectories(repoContentsPath.FullName);

            foreach (var directory in directories)
            {
                await ProcessDirectoryAsync(job, repoContentsPath, directory, baseCommitSha, branch, detectorVersion, experimentsManager);
            }
        }
        catch (Exception ex)
        {
            error = JobErrorBase.ErrorFromException(ex, _jobId, repoContentsPath.FullName);
        }

        if (error is not null)
        {
            await _apiHandler.RecordUpdateJobError(error, _logger);
            result = 1;
        }

        await _apiHandler.MarkAsProcessed(new(baseCommitSha));
        return result;
    }

    private async Task ProcessDirectoryAsync(
        Job job,
        DirectoryInfo repoContentsPath,
        string directory,
        string baseCommitSha,
        string branch,
        string detectorVersion,
        ExperimentsManager experimentsManager)
    {
        DependencySubmissionPayload payload;

        try
        {
            var discovery = await _discoveryWorker.RunAsync(repoContentsPath.FullName, directory);

            if (!discovery.IsSuccess && discovery.Error is not null)
            {
                _logger.Warn($"Discovery failed for directory '{directory}': {discovery.Error.GetReport()}");
                payload = DependencyGrapher.BuildFailedSubmission(
                    directory, _jobId, baseCommitSha, branch, detectorVersion,
                    discovery.Error.GetType().Name);
            }
            else
            {
                payload = DependencyGrapher.BuildSubmission(
                    discovery, _jobId, baseCommitSha, branch, detectorVersion);
            }

            _logger.Info($"Dependency submission payload for '{directory}':\n{JsonSerializer.Serialize(payload, SerializerOptions)}");
            await _apiHandler.CreateDependencySubmission(payload);
        }
        catch (Exception ex)
        {
            _logger.Warn($"Failed to process directory '{directory}': {ex.Message}");

            // Submit a failed snapshot so the service knows this directory was processed
            payload = DependencyGrapher.BuildFailedSubmission(
                directory, _jobId, baseCommitSha, branch, detectorVersion,
                "unknown_error");

            try
            {
                await _apiHandler.CreateDependencySubmission(payload);
            }
            catch (Exception submitEx)
            {
                _logger.Error($"Failed to submit failed snapshot for '{directory}': {submitEx.Message}");
            }
        }
    }

    private static string DetectDefaultBranch(DirectoryInfo repoContentsPath)
    {
        try
        {
            var process = new System.Diagnostics.Process
            {
                StartInfo = new System.Diagnostics.ProcessStartInfo
                {
                    FileName = "git",
                    Arguments = "symbolic-ref --short refs/remotes/origin/HEAD",
                    WorkingDirectory = repoContentsPath.FullName,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                },
            };
            process.Start();
            var output = process.StandardOutput.ReadToEnd().Trim();
            process.WaitForExit();

            if (process.ExitCode == 0 && !string.IsNullOrEmpty(output))
            {
                var branch = output.Replace("origin/", "");
                return $"refs/heads/{branch}";
            }
        }
        catch
        {
            // fall through to default
        }

        return "refs/heads/main";
    }

    private static string GetDetectorVersion()
    {
        var assembly = typeof(GraphWorker).Assembly;
        var version = assembly.GetName().Version?.ToString() ?? "0.0.0";
        return version;
    }

    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };
}
