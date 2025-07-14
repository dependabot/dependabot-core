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
        var expectedTitle = "Bump Package1 and 9 others";
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
        var actualCommitMessage = PullRequestTextGenerator.GetPullRequestCommitMessage(job, updateOperationsPerformedImmutable, dependencyGroupName).Replace("\r", "");
        var actualBody = PullRequestTextGenerator.GetPullRequestBody(job, updateOperationsPerformedImmutable, dependencyGroupName).Replace("\r", "");
        Assert.Equal(expectedTitle, actualTitle);
        Assert.Equal(expectedCommitMessage.Replace("\r", ""), actualCommitMessage);
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
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Bump Some.Package from 1.0.0 to 1.2.3",
            // expectedCommitMessage
            "Bump Some.Package from 1.0.0 to 1.2.3",
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package from 1.0.0 to 1.2.3
            """
        ];

        // single dependency, prefix given, ends with space
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
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "[SECURITY] Bump Some.Package from 1.0.0 to 1.2.3",
            // expectedCommitMessage
            "[SECURITY] Bump Some.Package from 1.0.0 to 1.2.3",
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package from 1.0.0 to 1.2.3
            """
        ];

        // single dependency, prefix given, ends with character or bracket
        yield return
        [
            // job
            FromCommitOptions(new(){ Prefix = "chore(deps)" }),
            // updateOperationsPerformed
            new UpdateOperationBase[]
            {
                new DirectUpdate()
                {
                    DependencyName = "Some.Package",
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "chore(deps): Bump Some.Package from 1.0.0 to 1.2.3",
            // expectedCommitMessage
            "chore(deps): Bump Some.Package from 1.0.0 to 1.2.3",
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package from 1.0.0 to 1.2.3
            """
        ];

        // single dependency, multiple versions
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
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Some.Package",
                    OldVersion = NuGetVersion.Parse("4.0.0"),
                    NewVersion = NuGetVersion.Parse("4.5.6"),
                    UpdatedFiles = ["b.txt"]
                },
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Bump Some.Package to 1.2.3, 4.5.6",
            // expectedCommitMessage
            "Bump Some.Package to 1.2.3, 4.5.6",
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package from 1.0.0 to 1.2.3
            - Updated Some.Package from 4.0.0 to 4.5.6
            """
        ];

        // two dependencies, two versions each
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
                    OldVersion = NuGetVersion.Parse("0.1.0"),
                    NewVersion = NuGetVersion.Parse("1.0.0"),
                    UpdatedFiles = ["a1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.A",
                    OldVersion = NuGetVersion.Parse("0.2.0"),
                    NewVersion = NuGetVersion.Parse("2.0.0"),
                    UpdatedFiles = ["a2.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    OldVersion = NuGetVersion.Parse("0.3.0"),
                    NewVersion = NuGetVersion.Parse("3.0.0"),
                    UpdatedFiles = ["b1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    OldVersion = NuGetVersion.Parse("0.4.0"),
                    NewVersion = NuGetVersion.Parse("4.0.0"),
                    UpdatedFiles = ["b2.txt"]
                },
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Bump Package.A and Package.B",
            // expectedCommitMessage
            """
            Bump Package.A and Package.B

            Bumps Package.A to 1.0.0, 2.0.0
            Bumps Package.B to 3.0.0, 4.0.0
            """,
            // expectedBody
            """
            Performed the following updates:
            - Updated Package.A from 0.1.0 to 1.0.0
            - Updated Package.A from 0.2.0 to 2.0.0
            - Updated Package.B from 0.3.0 to 3.0.0
            - Updated Package.B from 0.4.0 to 4.0.0
            """
        ];

        // four dependencies, two versions each
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
                    OldVersion = NuGetVersion.Parse("0.1.0"),
                    NewVersion = NuGetVersion.Parse("1.0.0"),
                    UpdatedFiles = ["a1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.A",
                    OldVersion = NuGetVersion.Parse("0.2.0"),
                    NewVersion = NuGetVersion.Parse("2.0.0"),
                    UpdatedFiles = ["a2.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    OldVersion = NuGetVersion.Parse("0.3.0"),
                    NewVersion = NuGetVersion.Parse("3.0.0"),
                    UpdatedFiles = ["b1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    OldVersion = NuGetVersion.Parse("0.4.0"),
                    NewVersion = NuGetVersion.Parse("4.0.0"),
                    UpdatedFiles = ["b2.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.C",
                    OldVersion = NuGetVersion.Parse("0.5.0"),
                    NewVersion = NuGetVersion.Parse("5.0.0"),
                    UpdatedFiles = ["c1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.C",
                    OldVersion = NuGetVersion.Parse("0.6.0"),
                    NewVersion = NuGetVersion.Parse("6.0.0"),
                    UpdatedFiles = ["c2.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.D",
                    OldVersion = NuGetVersion.Parse("0.7.0"),
                    NewVersion = NuGetVersion.Parse("7.0.0"),
                    UpdatedFiles = ["d1.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.D",
                    OldVersion = NuGetVersion.Parse("0.8.0"),
                    NewVersion = NuGetVersion.Parse("8.0.0"),
                    UpdatedFiles = ["d2.txt"]
                },
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Bump Package.A, Package.B, Package.C and Package.D",
            // expectedCommitMessage
            """
            Bump Package.A, Package.B, Package.C and Package.D

            Bumps Package.A to 1.0.0, 2.0.0
            Bumps Package.B to 3.0.0, 4.0.0
            Bumps Package.C to 5.0.0, 6.0.0
            Bumps Package.D to 7.0.0, 8.0.0
            """,
            // expectedBody
            """
            Performed the following updates:
            - Updated Package.A from 0.1.0 to 1.0.0
            - Updated Package.A from 0.2.0 to 2.0.0
            - Updated Package.B from 0.3.0 to 3.0.0
            - Updated Package.B from 0.4.0 to 4.0.0
            - Updated Package.C from 0.5.0 to 5.0.0
            - Updated Package.C from 0.6.0 to 6.0.0
            - Updated Package.D from 0.7.0 to 7.0.0
            - Updated Package.D from 0.8.0 to 8.0.0
            """
        ];

        // group with one update
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
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            "test-group",
            // expectedTitle
            "Bump the test-group group with 1 update",
            // expectedCommitMessage
            """
            Bump the test-group group with 1 update

            Bumps Some.Package from 1.0.0 to 1.2.3
            """,
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package from 1.0.0 to 1.2.3
            """
        ];

        // group with multiple updates
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
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Package.B",
                    OldVersion = NuGetVersion.Parse("4.0.0"),
                    NewVersion = NuGetVersion.Parse("4.5.6"),
                    UpdatedFiles = ["a.txt"]
                }
            },
            // dependencyGroupName
            "test-group",
            // expectedTitle
            "Bump the test-group group with 2 updates",
            // expectedCommitMessage
            """
            Bump the test-group group with 2 updates

            Bumps Package.A from 1.0.0 to 1.2.3
            Bumps Package.B from 4.0.0 to 4.5.6
            """,
            // expectedBody
            """
            Performed the following updates:
            - Updated Package.A from 1.0.0 to 1.2.3
            - Updated Package.B from 4.0.0 to 4.5.6
            """
        ];

        // multiple updates to the same dependency
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
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["a.txt"]
                },
                new DirectUpdate()
                {
                    DependencyName = "Some.Package",
                    OldVersion = NuGetVersion.Parse("1.0.0"),
                    NewVersion = NuGetVersion.Parse("1.2.3"),
                    UpdatedFiles = ["b.txt"]
                }
            },
            // dependencyGroupName
            null,
            // expectedTitle
            "Bump Some.Package to 1.2.3",
            // expectedCommitMessage
            """
            Bump Some.Package to 1.2.3
            """,
            // expectedBody
            """
            Performed the following updates:
            - Updated Some.Package from 1.0.0 to 1.2.3
            - Updated Some.Package from 1.0.0 to 1.2.3
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
