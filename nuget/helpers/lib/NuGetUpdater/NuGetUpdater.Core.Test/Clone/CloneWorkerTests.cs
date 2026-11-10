using NuGetUpdater.Core.Clone;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Run;

using Xunit;

namespace NuGetUpdater.Core.Test.Clone;

public class CloneWorkerTests
{
    private const string TestRepoPath = "TEST/REPO/PATH";

    [Fact]
    public void AdoCloneCommandsAreGenerated()
    {
        TestCommands(
            provider: "azure",
            repoMoniker: "OrganizationName/ProjectName/_git/RepositoryName",
            expectedCommands:
            [
                (["clone", "--no-tags", "--depth", "1", "--recurse-submodules", "--shallow-submodules", "https://dev.azure.com/OrganizationName/ProjectName/_git/RepositoryName", TestRepoPath], null)
            ]
        );
    }

    [Fact]
    public void AdoOnPremCloneCommandsAreGenerated()
    {
        TestCommands(
            provider: "azure",
            hostname: "azure-onprem-url.domain.org",
            repoMoniker: "CollectionName/ProjectName/_git/RepositoryName",
            expectedCommands:
            [
                (["clone", "--no-tags", "--depth", "1", "--recurse-submodules", "--shallow-submodules", "https://azure-onprem-url.domain.org/CollectionName/ProjectName/_git/RepositoryName", TestRepoPath], null)
            ]
        );
    }

    [Fact]
    public void CloneCommandsAreGenerated()
    {
        TestCommands(
            provider: "github",
            repoMoniker: "test/repo",
            expectedCommands:
            [
                (["clone", "--no-tags", "--depth", "1", "--recurse-submodules", "--shallow-submodules", "https://github.com/test/repo", TestRepoPath], null)
            ]
        );
    }

    [Fact]
    public void GheOnPremCloneCommandsAreGenerated()
    {
        TestCommands(
            provider: "github",
            hostname: "ghe-onprem-url.example.com",
            repoMoniker: "OwnerName/RepoName",
            expectedCommands:
            [
                (["clone", "--no-tags", "--depth", "1", "--recurse-submodules", "--shallow-submodules", "https://ghe-onprem-url.example.com/OwnerName/RepoName", TestRepoPath], null)
            ]
        );
    }

    [Fact]
    public void CloneCommandsAreGeneratedWhenBranchIsSpecified()
    {
        TestCommands(
            provider: "github",
            repoMoniker: "test/repo",
            branch: "some-branch",
            expectedCommands:
            [
                (["clone", "--no-tags", "--depth", "1", "--recurse-submodules", "--shallow-submodules", "--branch", "some-branch", "--single-branch", "https://github.com/test/repo", TestRepoPath], null)
            ]
        );
    }

    [Fact]
    public void CloneCommandsAreGeneratedWhenCommitIsSpecified()
    {
        TestCommands(
            provider: "github",
            repoMoniker: "test/repo",
            commit: "abc123",
            expectedCommands:
            [
                (["clone", "--no-tags", "--depth", "1", "--recurse-submodules", "--shallow-submodules", "https://github.com/test/repo", TestRepoPath], null),
                (["fetch", "--depth", "1", "--recurse-submodules=on-demand", "origin", "abc123"], TestRepoPath),
                (["reset", "--hard", "--recurse-submodules", "abc123"], TestRepoPath)
            ]
        );
    }

    [Fact]
    public async Task SuccessfulCloneGeneratesNoApiMessages()
    {
        await TestCloneAsync(
            provider: "github",
            repoMoniker: "test/repo",
            expectedApiMessages: []
        );
    }

    [Fact]
    public async Task UnauthorizedCloneGeneratesTheExpectedApiMessagesFromGenericOutput()
    {
        await TestCloneAsync(
            provider: "github",
            repoMoniker: "test/repo",
            testGitCommandHandler: new TestGitCommandHandlerWithOutputs(GitCommandExitCodes.Failure, "Authentication failed for repo", "", new TestLogger()),
            expectedApiMessages:
            [
                new JobRepoNotFound("Authentication failed for repo"),
                new MarkAsProcessed("unknown"),
            ],
            expectedExitCode: 1
        );
    }

    [Fact]
    public async Task UnauthorizedCloneGeneratesTheExpectedApiMessagesFromGitCommandOutput()
    {
        await TestCloneAsync(
            provider: "github",
            repoMoniker: "test/repo",
            testGitCommandHandler: new TestGitCommandHandlerWithOutputs(GitCommandExitCodes.Failure, "", "fatal: could not read Username for 'https://github.com': No such device or address", new TestLogger()),
            expectedApiMessages:
            [
                new JobRepoNotFound("fatal: could not read Username for 'https://github.com': No such device or address"),
                new MarkAsProcessed("unknown"),
            ],
            expectedExitCode: 1
        );
    }

    [Fact]
    public async Task JobFileParseErrorIsReported_InvalidJson()
    {
        // arrange
        TestApiHandler testApiHandler = new();
        TestGitCommandHandler testGitCommandHandler = new();
        CloneWorker cloneWorker = new("JOB-ID", testApiHandler, testGitCommandHandler, new TestLogger());
        using TemporaryDirectory testDirectory = new();
        string jobFilePath = Path.Combine(testDirectory.DirectoryPath, "job.json");
        await File.WriteAllTextAsync(jobFilePath, "not json", TestContext.Current.CancellationToken);

        // act
        int result = await cloneWorker.RunAsync(new FileInfo(jobFilePath), new DirectoryInfo(testDirectory.DirectoryPath));

        // assert
        Assert.Equal(1, result);
        (Type Type, object Object) expectedParseErrorObject = testApiHandler.ReceivedMessages.First(m => m.Type == typeof(UnknownError));
        UnknownError unknownError = (UnknownError)expectedParseErrorObject.Object;
        Assert.Equal("JsonException", unknownError.Details["error-class"]);
    }

    [Fact]
    public async Task JobFileParseErrorIsReported_BadRequirement()
    {
        // arrange
        TestApiHandler testApiHandler = new();
        TestGitCommandHandler testGitCommandHandler = new();
        CloneWorker cloneWorker = new("JOB-ID", testApiHandler, testGitCommandHandler, new TestLogger());
        using TemporaryDirectory testDirectory = new();
        string jobFilePath = Path.Combine(testDirectory.DirectoryPath, "job.json");

        // write a job file with a valid shape, but invalid requirement
        await File.WriteAllTextAsync(jobFilePath, """
            {
                "job": {
                    "source": {
                        "provider": "github",
                        "repo": "test/repo"
                    },
                    "security-advisories": [
                        {
                            "dependency-name": "Some.Dependency",
                            "affected-versions": ["not a valid requirement"]
                        }
                    ]
                }
            }
            """, TestContext.Current.CancellationToken);

        // act
        int result = await cloneWorker.RunAsync(new FileInfo(jobFilePath), new DirectoryInfo(testDirectory.DirectoryPath));

        // assert
        Assert.Equal(1, result);
        (Type Type, object Object) expectedParseErrorObject = testApiHandler.ReceivedMessages.Single(m => m.Type == typeof(BadRequirement));
        BadRequirement badRequirement = (BadRequirement)expectedParseErrorObject.Object;
        Assert.Equal("not a valid requirement", badRequirement.Details["message"]);
    }

    [Fact]
    public async Task FailureToCloneGeneratesTheExpectedApiMessagesFromGitCommandOutput()
    {
        await TestCloneAsync(
            provider: "github",
            repoMoniker: "test/repo",
            testGitCommandHandler: new TestGitCommandHandlerWithOutputs(GitCommandExitCodes.Failure, "StdOut Message", "StdErr Message", new TestLogger()),
            expectedApiMessages:
            [
                new UnknownError(new InvalidOperationException($"Git command failed with exit code {GitCommandExitCodes.Failure}."), "TEST-JOB-ID"),
                new MarkAsProcessed("unknown"),
            ],
            expectedExitCode: 1
        );
    }

    private class TestGitCommandHandlerWithOutputs : TestGitCommandHandler
    {
        private readonly int _exitCode;
        private readonly string _stdout;
        private readonly string _stderr;
        private readonly ILogger _logger;

        public TestGitCommandHandlerWithOutputs(int exitCode, string stdout, string stderr, ILogger logger)
        {
            _exitCode = exitCode;
            _stdout = stdout;
            _stderr = stderr;
            _logger = logger;
        }

        public override async Task RunGitCommandAsync(IReadOnlyCollection<string> args, string? workingDirectory = null)
        {
            await base.RunGitCommandAsync(args, workingDirectory);
            ShellGitCommandHandler.HandleErrorsFromOutput(_exitCode, _stdout, _stderr, _logger);
        }
    }

    private static void TestCommands(string provider, string repoMoniker, (string[] Args, string? WorkingDirectory)[] expectedCommands, string? branch = null, string? commit = null, string? hostname = null)
    {
        Job job = new()
        {
            Source = new()
            {
                Provider = provider,
                Hostname = hostname,
                Repo = repoMoniker,
                Branch = branch,
                Commit = commit,
            }
        };
        (string[] Args, string? WorkingDirectory)[] actualCommands = CloneWorker.GetAllCommandArgs(job, TestRepoPath);
        VerifyCommands(expectedCommands, actualCommands);
    }

    private static async Task TestCloneAsync(string provider, string repoMoniker, object[] expectedApiMessages, string? branch = null, string? commit = null, TestGitCommandHandler? testGitCommandHandler = null, int expectedExitCode = 0)
    {
        // arrange
        TestApiHandler testApiHandler = new();
        testGitCommandHandler ??= new TestGitCommandHandler();
        CloneWorker worker = new("TEST-JOB-ID", testApiHandler, testGitCommandHandler, new TestLogger());

        // act
        Job job = new()
        {
            Source = new()
            {
                Provider = provider,
                Repo = repoMoniker,
                Branch = branch,
                Commit = commit,
            }
        };
        int exitCode = await worker.RunAsync(job, TestRepoPath);

        // assert
        Assert.Equal(expectedExitCode, exitCode);

        (Type Type, object Object)[] actualApiMessages = testApiHandler.ReceivedMessages.ToArray();
        if (actualApiMessages.Length > expectedApiMessages.Length)
        {
            string[] extraApiMessages = actualApiMessages.Skip(expectedApiMessages.Length).Select(m => EndToEndTests.SerializeObjectAndType(m.Object)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but got {extraApiMessages.Length} extra:\n\t{string.Join("\n\t", extraApiMessages)}");
        }
        if (expectedApiMessages.Length > actualApiMessages.Length)
        {
            string[] missingApiMessages = expectedApiMessages.Skip(actualApiMessages.Length).Select(m => EndToEndTests.SerializeObjectAndType(m)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but only got {actualApiMessages.Length}; missing:\n\t{string.Join("\n\t", missingApiMessages)}");
        }
    }

    private static void VerifyCommands((string[] Args, string? WorkingDirectory)[] expected, (string[] Args, string? WorkingDirectory)[] actual)
    {
        string[] expectedCommands = StringifyCommands(expected);
        string[] actualCommands = StringifyCommands(actual);
        Assert.True(expectedCommands.Length == actualCommands.Length, $"Expected {expectedCommands.Length} messages:\n\t{string.Join("\n\t", expectedCommands)}\ngot {actualCommands.Length}:\n\t{string.Join("\n\t", actualCommands)}");
        foreach ((string? expectedCommand, string? actualCommand) in expectedCommands.Zip(actualCommands))
        {
            Assert.Equal(expectedCommand, actualCommand);
        }
    }

    private static string[] StringifyCommands((string[] Args, string? WorkingDirectory)[] commandArgs) => commandArgs.Select(a => StringifyCommand(a.Args, a.WorkingDirectory)).ToArray();
    private static string StringifyCommand(string[] args, string? workingDirectory) => $"args=[{string.Join(", ", args)}], workingDirectory={ReplaceWorkingDirectory(workingDirectory)}";
    private static string ReplaceWorkingDirectory(string? arg) => arg ?? "NULL";

    private static class GitCommandExitCodes
    {
        public const int Success = 0;
        public const int Failure = 1;
    }
}
