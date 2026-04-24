using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Graph;

public class GraphWorker : IGraphWorker
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

    public async Task<int> RunAsync(FileInfo jobFilePath, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha)
    {
        // Deserialize the job file
        var jobFileContent = await File.ReadAllTextAsync(jobFilePath.FullName);
        var jobWrapper = RunWorker.Deserialize(jobFileContent);
        var job = jobWrapper.Job;
        var experimentsManager = ExperimentsManager.GetExperimentsManager(job.Experiments);

        // Use the case-insensitive repo contents path if provided, otherwise use the original
        var actualRepoContentsPath = caseInsensitiveRepoContentsPath ?? repoContentsPath;

        int result = 0;
        JobErrorBase? error = null;

        try
        {
            // Process each directory in the job
            foreach (var directory in job.GetAllDirectories(actualRepoContentsPath.FullName))
            {
                _logger.Info($"Running dependency discovery for directory: {directory}");

                // Run dependency discovery
                var discoveryResult = await _discoveryWorker.RunAsync(actualRepoContentsPath.FullName, directory);

                // Check for discovery errors
                if (discoveryResult.Error is not null)
                {
                    _logger.Error($"Discovery error in {directory}: {discoveryResult.Error.GetReport()}");
                    await _apiHandler.RecordUpdateJobError(discoveryResult.Error, _logger);
                    error = discoveryResult.Error;
                    result = 1;
                    continue;
                }

                // Build the dependency submission from the discovery results
                var submission = BuildDependencySubmission(
                    discoveryResult,
                    job,
                    baseCommitSha,
                    repoContentsPath.FullName,
                    directory);

                // Submit the dependency graph
                _logger.Info($"Submitting dependency graph for {directory}");
                await _apiHandler.CreateDependencySubmission(submission);
            }
        }
        catch (Exception ex)
        {
            error = JobErrorBase.ErrorFromException(ex, _jobId, actualRepoContentsPath.FullName);
            await _apiHandler.RecordUpdateJobError(error, _logger);
            result = 1;
        }

        // Mark the job as processed
        await _apiHandler.MarkAsProcessed(new(baseCommitSha));

        return result;
    }

    internal CreateDependencySubmission BuildDependencySubmission(
        WorkspaceDiscoveryResult discoveryResult,
        Job job,
        string baseCommitSha,
        string repoRoot,
        string directory)
    {
        var manifests = new Dictionary<string, CreateDependencySubmission.Manifest>();
        string status = "ok";
        string? reason = null;

        // If no projects were discovered, return a skipped submission
        if (discoveryResult.Projects.IsEmpty)
        {
            _logger.Info($"No projects discovered in {directory}");
            status = "skipped";
            reason = "missing manifest files";
        }
        else
        {
            // Process each project
            foreach (var project in discoveryResult.Projects)
            {
                var combinedPath = PathHelper.JoinPath(discoveryResult.Path, project.FilePath).NormalizePathToUnix();
                var manifestPath = $"/{combinedPath}";
                var sourceLocation = combinedPath;

                var resolvedDependencies = new Dictionary<string, CreateDependencySubmission.ResolvedDependency>();

                // Process each dependency
                foreach (var dependency in project.Dependencies)
                {
                    if (string.IsNullOrEmpty(dependency.Version))
                    {
                        continue; // Skip dependencies without versions
                    }

                    // Create package URL (PURL format: pkg:nuget/PackageName@version)
                    var packageUrl = $"pkg:nuget/{dependency.Name}@{dependency.Version}";

                    // Determine relationship (direct vs indirect)
                    var relationship = dependency.IsTopLevel ? "direct" : "indirect";

                    // Determine scope (runtime, development, etc.)
                    var scope = dependency.Type switch
                    {
                        DependencyType.PackageReference => "runtime",
                        DependencyType.PackageVersion => "runtime",
                        _ => "runtime"
                    };

                    resolvedDependencies[packageUrl] = new CreateDependencySubmission.ResolvedDependency
                    {
                        PackageUrl = packageUrl,
                        Relationship = relationship,
                        Scope = scope,
                        Dependencies = [] // TODO: Add transitive dependencies if available
                    };
                }

                // Only add manifest if it has dependencies
                if (resolvedDependencies.Count > 0)
                {
                    manifests[manifestPath] = new CreateDependencySubmission.Manifest
                    {
                        Name = manifestPath,
                        File = new CreateDependencySubmission.ManifestFile
                        {
                            SourceLocation = sourceLocation
                        },
                        Metadata = new CreateDependencySubmission.ManifestMetadata
                        {
                            Ecosystem = "nuget"
                        },
                        Resolved = resolvedDependencies
                    };
                }
            }

            // If no manifests with dependencies, mark as skipped
            if (manifests.Count == 0)
            {
                _logger.Info($"No dependencies found in {directory}");
                status = "skipped";
                reason = "missing manifest files";
            }
        }

        // Build the submission (always return a submission, even if skipped)
        return new CreateDependencySubmission
        {
            Version = 1,
            Sha = baseCommitSha,
            Ref = $"refs/heads/{job.Source.Branch ?? "main"}",
            Job = new CreateDependencySubmission.SubmissionJob
            {
                Correlator = $"dependabot-nuget-{directory.Replace("/", "-").TrimStart('-')}",
                Id = _jobId
            },
            Detector = new CreateDependencySubmission.SubmissionDetector
            {
                Name = "dependabot",
                Version = "0.372.0", // TODO: Get actual version
                Url = "https://github.com/dependabot/dependabot-core"
            },
            Manifests = manifests,
            Metadata = new CreateDependencySubmission.SubmissionMetadata
            {
                Status = status,
                ScannedManifestPath = $"nuget::{directory}",
                Reason = reason
            }
        };
    }
}

