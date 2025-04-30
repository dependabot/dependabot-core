using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class PullRequestTextTests
{
    [Fact]
    public void LongPullRequestTitleIsTrimmed()
    {
        var job = FromCommitOptions(null);
        var updateOperations = new List<UpdateOperationBase>();
        for (int i = 1; i <= 10; i++)
        {
            updateOperations.Add(new DirectUpdate()
            {
                DependencyName = $"Package{i}",
                NewVersion = NuGetVersion.Parse($"{i}.0.0"),
                UpdatedFiles = ["file.txt"],
            });
        }

        var actualTitle = PullRequestTextGenerator.GetPullRequestTitle(job, [.. updateOperations], dependencyGroupName: null);
        var expectedTitle = "Update Package1 and 9 other dependencies";
        Assert.Equal(expectedTitle, actualTitle);
    }

    [Theory]
    [MemberData(nameof(GetPullRequestTextTestData))]
    public void PullRequestText(
        Job job,
        UpdateOperationBase[] updateOperationsPerformed,
        string? dependencyGroupName,
        string expectedTitle,
        string expectedCommitMessage,
        string expectedBody
    )
    {
        var updateOperationsPerformedImmutable = updateOperationsPerformed.ToImmutableArray();
        var actualTitle = PullRequestTextGenerator.GetPullRequestTitle(job, updateOperationsPerformedImmutable, dependencyGroupName);
        var actualCommitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, updateOperationsPerformedImmutable, dependencyGroupName);
        var actualBody = PullRequestTextGenerator.GetPullRequestBody(job, updateOperationsPerformedImmutable, dependencyGroupName);
        Assert.Equal(expectedTitle, actualTitle);
        Assert.Equal(expectedCommitMessage, actualCommitMessage);
        Assert.Equal(expectedBody.Replace("\r", ""), actualBody);
    }

    public static IEnumerable<object?[]> GetPullRequestTextTestData()
    {
        // single dependency, no optional values
        yield return
        [
            // job
            FromCommitOptions(null),
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Package",
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Update Some.Package to 1.2.3",
            // expectedCommitMessage
            "Update Some.Package to 1.2.3",
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package to 1.2.3 in a.txt
            """
        ];

        // single dependency, prefix given
        yield return
        [
            // job
            FromCommitOptions(new(){ Prefix = "[SECURITY] " }),
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Package",
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "[SECURITY] Update Some.Package to 1.2.3",
            // expectedCommitMessage
            "Update Some.Package to 1.2.3",
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package to 1.2.3 in a.txt
            """
        ];

        // multiple dependencies, multiple versions
        yield return
        [
            // job
            FromCommitOptions(null),
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Package.A",
                    NewVersion = NuGetVersion.Parse("1.0.0"),
                    UpdatedFiles = ["a1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.A",
                    NewVersion = NuGetVersion.Parse("2.0.0"),
                    UpdatedFiles = ["a2.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    NewVersion = NuGetVersion.Parse("3.0.0"),
                    UpdatedFiles = ["b1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    NewVersion = NuGetVersion.Parse("4.0.0"),
                    UpdatedFiles = ["b2.txt"]
                },
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Update Package.A to 1.0.0, 2.0.0; Package.B to 3.0.0, 4.0.0",
            // expectedCommitMessage
            """
            Update:
            - Package.A to 1.0.0, 2.0.0
            - Package.B to 3.0.0, 4.0.0
            """,
            // expectedBody
            """
            Performed the following updates:
            - Updated Package.A to 1.0.0 in a1.txt
            - Updated Package.A to 2.0.0 in a2.txt
            - Updated Package.B to 3.0.0 in b1.txt
            - Updated Package.B to 4.0.0 in b2.txt
            """
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
