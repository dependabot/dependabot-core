using NuGetUpdater.Core.Clone;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Run;

using Xunit;

namespace NuGetUpdater.Core.Test.Clone;

public class CloneWorkerTests
{
    private const string TestRepoPath = "TEST/REPO/PATH";

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
            testGitCommandHandler: new TestGitCommandHandlerWithOutputs("Authentication failed for repo", ""),
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
            testGitCommandHandler: new TestGitCommandHandlerWithOutputs("", "fatal: could not read Username for 'https://github.com': No such device or address"),
            expectedApiMessages:
            [
                new JobRepoNotFound("fatal: could not read Username for 'https://github.com': No such device or address"),
                new MarkAsProcessed("unknown"),
            ],
            expectedExitCode: 1
        );
    }

    private class TestGitCommandHandlerWithOutputs : TestGitCommandHandler
    {
        private readonly string _stdout;
        private readonly string _stderr;

        public TestGitCommandHandlerWithOutputs(string stdout, string stderr)
        {
            _stdout = stdout;
            _stderr = stderr;
        }

        public override async Task RunGitCommandAsync(IReadOnlyCollection<string> args, string? workingDirectory = null)
        {
            await base.RunGitCommandAsync(args, workingDirectory);
            ShellGitCommandHandler.HandleErrorsFromOutput(_stdout, _stderr);
        }
    }

    private static void TestCommands(string provider, string repoMoniker, (string[] Args, string? WorkingDirectory)[] expectedCommands, string? branch = null, string? commit = null)
    {
        var job = new Job()
        {
            Source = new()
            {
                Provider = provider,
                Repo = repoMoniker,
                Branch = branch,
                Commit = commit,
            }
        };
        var actualCommands = CloneWorker.GetAllCommandArgs(job, TestRepoPath);
        VerifyCommands(expectedCommands, actualCommands);
    }

    private static async Task TestCloneAsync(string provider, string repoMoniker, object[] expectedApiMessages, string? branch = null, string? commit = null, TestGitCommandHandler? testGitCommandHandler = null, int expectedExitCode = 0)
    {
        // arrange
        var testApiHandler = new TestApiHandler();
        testGitCommandHandler ??= new TestGitCommandHandler();
        var testLogger = new TestLogger();
        var worker = new CloneWorker(testApiHandler, testGitCommandHandler, testLogger);

        // act
        var job = new Job()
        {
            Source = new()
            {
                Provider = provider,
                Repo = repoMoniker,
                Branch = branch,
                Commit = commit,
            }
        };
        var exitCode = await worker.RunAsync(job, TestRepoPath);

        // assert
        Assert.Equal(expectedExitCode, exitCode);

        var actualApiMessages = testApiHandler.ReceivedMessages.ToArray();
        if (actualApiMessages.Length > expectedApiMessages.Length)
        {
            var extraApiMessages = actualApiMessages.Skip(expectedApiMessages.Length).Select(m => RunWorkerTests.SerializeObjectAndType(m.Object)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but got {extraApiMessages.Length} extra:\n\t{string.Join("\n\t", extraApiMessages)}");
        }
        if (expectedApiMessages.Length > actualApiMessages.Length)
        {
            var missingApiMessages = expectedApiMessages.Skip(actualApiMessages.Length).Select(m => RunWorkerTests.SerializeObjectAndType(m)).ToArray();
            Assert.Fail($"Expected {expectedApiMessages.Length} API messages, but only got {actualApiMessages.Length}; missing:\n\t{string.Join("\n\t", missingApiMessages)}");
        }
    }

    private static void VerifyCommands((string[] Args, string? WorkingDirectory)[] expected, (string[] Args, string? WorkingDirectory)[] actual)
    {
        var expectedCommands = StringifyCommands(expected);
        var actualCommands = StringifyCommands(actual);
        Assert.True(expectedCommands.Length == actualCommands.Length, $"Expected {expectedCommands.Length} messages:\n\t{string.Join("\n\t", expectedCommands)}\ngot {actualCommands.Length}:\n\t{string.Join("\n\t", actualCommands)}");
        foreach (var (expectedCommand, actualCommand) in expectedCommands.Zip(actualCommands))
        {
            Assert.Equal(expectedCommand, actualCommand);
        }
    }

    private static string[] StringifyCommands((string[] Args, string? WorkingDirectory)[] commandArgs) => commandArgs.Select(a => StringifyCommand(a.Args, a.WorkingDirectory)).ToArray();
    private static string StringifyCommand(string[] args, string? workingDirectory) => $"args=[{string.Join(", ", args)}], workingDirectory={ReplaceWorkingDirectory(workingDirectory)}";
    private static string ReplaceWorkingDirectory(string? arg) => arg ?? "NULL";
}
