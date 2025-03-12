using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class PullRequestTextTests
{
    [Theory]
    [MemberData(nameof(GetPullRequestTextTestData))]
    public void PullRequestText(Job job, ReportedDependency[] updatedDependencies, DependencyFile[] updatedFiles, string? dependencyGroupName, string expectedTitle, string expectedCommitMessage, string expectedBody)
    {
        var actualTitle = PullRequestTextGenerator.GetPullRequestTitle(job, updatedDependencies, updatedFiles, dependencyGroupName);
        var actualCommitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, updatedDependencies, updatedFiles, dependencyGroupName);
        var actualBody = PullRequestTextGenerator.GetPullRequestBody(job, updatedDependencies, updatedFiles, dependencyGroupName);
        Assert.Equal(expectedTitle, actualTitle);
        Assert.Equal(expectedCommitMessage, actualCommitMessage);
        Assert.Equal(expectedBody, actualBody);
    }

    public static IEnumerable<object?[]> GetPullRequestTextTestData()
    {
        // single dependency, no optional values
        yield return
        [
            // job
            FromCommitOptions(null),
            // updatedDependencies
            new []
            {
                new ReportedDependency()
                {
                    Name = "Some.Package",
                    Version = "1.2.3",
                    Requirements = []
                }
            },
            // updatedFiles
            Array.Empty<DependencyFile>(),
            // dependencyGroupName
            null,
            // expectedTitle
            "Update Some.Package to 1.2.3",
            // expectedCommitMessage
            "Update Some.Package to 1.2.3",
            // expectedBody
            "Update Some.Package to 1.2.3"
        ];

        // single dependency, prefix given
        yield return
        [
            // job
            FromCommitOptions(new(){ Prefix = "[SECURITY] " }),
            // updatedDependencies
            new []
            {
                new ReportedDependency()
                {
                    Name = "Some.Package",
                    Version = "1.2.3",
                    Requirements = []
                }
            },
            // updatedFiles
            Array.Empty<DependencyFile>(),
            // dependencyGroupName
            null,
            // expectedTitle
            "[SECURITY] Update Some.Package to 1.2.3",
            // expectedCommitMessage
            "[SECURITY] Update Some.Package to 1.2.3",
            // expectedBody
            "[SECURITY] Update Some.Package to 1.2.3"
        ];

        // multiple dependencies, multiple versions
        yield return
        [
            // job
            FromCommitOptions(null),
            // updatedDependencies
            new[]
            {
                new ReportedDependency()
                {
                    Name = "Package.A",
                    Version = "1.0.0",
                    Requirements = []
                },
                new ReportedDependency()
                {
                    Name = "Package.A",
                    Version = "2.0.0",
                    Requirements = []
                },
                new ReportedDependency()
                {
                    Name = "Package.B",
                    Version = "3.0.0",
                    Requirements = []
                },
                new ReportedDependency()
                {
                    Name = "Package.B",
                    Version = "4.0.0",
                    Requirements = []
                },
            },
            // updatedFiles
            Array.Empty<DependencyFile>(),
            // dependencyGroupName
            null,
            // expectedTitle
            "Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0",
            // expectedCommitMessage
            "Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0",
            // expectedBody
            "Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0"
        ];
    }

    private static Job FromCommitOptions(CommitOptions? commitOptions)
    {
        return new Job()
        {
            Source = new()
            {
                Provider = "github",
                Repo = "test/repo"
            },
            CommitMessageOptions = commitOptions,
        };
    }
}
