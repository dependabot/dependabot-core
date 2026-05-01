using System.Collections.Immutable;
using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Graph;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Graph;

public class GraphWorkerTests
{
    [Fact]
    public async Task RunAsync_SubmitsDependencySnapshot()
    {
        var apiHandler = new TestApiHandler();
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "App.csproj",
                    Dependencies =
                    [
                        new Dependency("Newtonsoft.Json", "13.0.1", DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };
        var discoveryWorker = new TestDiscoveryWorker(discovery);

        var job = new Job
        {
            Source = new JobSource
            {
                Provider = "github",
                Repo = "test/repo",
                Branch = "main",
                Directory = "/",
            },
        };

        var worker = new GraphWorker("job-123", apiHandler, discoveryWorker, new TestLogger());
        var experimentsManager = new ExperimentsManager();
        var result = await worker.RunAsync(
            job,
            new DirectoryInfo(Path.GetTempPath()),
            "abc123",
            experimentsManager);

        Assert.Equal(0, result);

        // Should have received: DependencySubmissionPayload + MarkAsProcessed
        var submissionMessages = apiHandler.ReceivedMessages
            .Where(m => m.Type == typeof(DependencySubmissionPayload))
            .ToList();
        Assert.Single(submissionMessages);

        var payload = (DependencySubmissionPayload)submissionMessages[0].Object;
        Assert.Equal("abc123", payload.Sha);
        Assert.Equal("refs/heads/main", payload.Ref);
        Assert.Equal("ok", payload.Metadata.Status);
        Assert.Single(payload.Manifests);
    }

    [Fact]
    public async Task RunAsync_WithEmptyDiscovery_SubmitsSkippedSnapshot()
    {
        var apiHandler = new TestApiHandler();
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects = [],
        };
        var discoveryWorker = new TestDiscoveryWorker(discovery);

        var job = new Job
        {
            Source = new JobSource
            {
                Provider = "github",
                Repo = "test/repo",
                Branch = "main",
                Directory = "/",
            },
        };

        var worker = new GraphWorker("job-123", apiHandler, discoveryWorker, new TestLogger());
        var experimentsManager = new ExperimentsManager();
        var result = await worker.RunAsync(
            job,
            new DirectoryInfo(Path.GetTempPath()),
            "abc123",
            experimentsManager);

        Assert.Equal(0, result);

        var submissionMessages = apiHandler.ReceivedMessages
            .Where(m => m.Type == typeof(DependencySubmissionPayload))
            .ToList();
        Assert.Single(submissionMessages);

        var payload = (DependencySubmissionPayload)submissionMessages[0].Object;
        Assert.Equal("skipped", payload.Metadata.Status);
        Assert.Equal("missing manifest files", payload.Metadata.Reason);
    }

    [Fact]
    public async Task RunAsync_AlwaysMarksAsProcessed()
    {
        var apiHandler = new TestApiHandler();
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects = [],
        };
        var discoveryWorker = new TestDiscoveryWorker(discovery);

        var job = new Job
        {
            Source = new JobSource
            {
                Provider = "github",
                Repo = "test/repo",
                Branch = "main",
                Directory = "/",
            },
        };

        var worker = new GraphWorker("job-123", apiHandler, discoveryWorker, new TestLogger());
        var experimentsManager = new ExperimentsManager();
        await worker.RunAsync(job, new DirectoryInfo(Path.GetTempPath()), "abc123", experimentsManager);

        var processedMessages = apiHandler.ReceivedMessages
            .Where(m => m.Type == typeof(MarkAsProcessed))
            .ToList();
        Assert.Single(processedMessages);
    }

    private class TestDiscoveryWorker : IDiscoveryWorker
    {
        private readonly WorkspaceDiscoveryResult _result;

        public TestDiscoveryWorker(WorkspaceDiscoveryResult result) => _result = result;

        public Task<WorkspaceDiscoveryResult> RunAsync(string repoRootPath, string workspacePath)
        {
            return Task.FromResult(_result);
        }
    }
}
