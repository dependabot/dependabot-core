using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class MessageReportTests
{
    [Fact]
    public void AllMessagesAreTested()
    {
        var untestedTypes = typeof(MessageBase).Assembly.GetTypes()
            .Where(t => t.IsSubclassOf(typeof(MessageBase)))
            .Where(t => t != typeof(JobErrorBase)) // this is an abstract class and can't be directly tested
            .ToHashSet();
        foreach (var data in MessageBaseTestData())
        {
            var testedMessageType = data[0]!.GetType();
            untestedTypes.Remove(testedMessageType);
        }

        Assert.Empty(untestedTypes.Select(t => t.Name));
    }

    [Theory]
    [MemberData(nameof(MessageBaseTestData))]
    public void MessageBase(MessageBase message, string expected)
    {
        var actual = message.GetReport().Replace("\r", "");
        Assert.Equal(expected.Replace("\r", ""), actual);
    }

    public static IEnumerable<object[]> MessageBaseTestData()
    {
        yield return
        [
            // message
            new BadRequirement("unparseable"),
            // expected
            """
            Error type: illformed_requirement
            - message: unparseable
            """
        ];

        yield return
        [
            // message
            new ClosePullRequest()
            {
                DependencyNames = ["Dependency1", "Dependency2"]
            },
            // expected
            """
            ClosePullRequest: up_to_date
            - Dependency1
            - Dependency2
            """
        ];

        yield return
        [
            // message
            new CreatePullRequest()
            {
                Dependencies = [
                    new()
                    {
                        Name = "Dependency1",
                        Version = "1.2.3",
                        Requirements = [], // unused
                    },
                    new()
                    {
                        Name = "Dependency2",
                        Version = "4.5.6",
                        Requirements = [], // unused
                    }
                ],
                UpdatedDependencyFiles = [], // unused
                BaseCommitSha = "unused",
                CommitMessage = "unused",
                PrTitle = "unused",
                PrBody = "unused",
                DependencyGroup = null, // unused
            },
            // expected
            """
            CreatePullRequest
            - Dependency1/1.2.3
            - Dependency2/4.5.6
            """
        ];

        yield return
        [
            // message
            new DependencyFileNotFound("path/to/file.txt", "custom message"),
            // expected
            """
            Error type: dependency_file_not_found
            - message: custom message
            - file-path: path/to/file.txt
            """
        ];

        yield return
        [
            // message
            new DependencyFileNotParseable("path/to/file.txt", "custom message"),
            // expected
            """
            Error type: dependency_file_not_parseable
            - message: custom message
            - file-path: path/to/file.txt
            """
        ];

        yield return
        [
            // message
            new DependencyNotFound("Some.Dependency"),
            // expected
            """
            Error type: dependency_not_found
            - source: Some.Dependency
            """
        ];

        yield return
        [
            // message
            new JobRepoNotFound("custom message"),
            // expected
            """
            Error type: job_repo_not_found
            - message: custom message
            """
        ];

        yield return
        [
            // message
            new PrivateSourceAuthenticationFailure(["url1", "url2"]),
            // expected
            """
            Error type: private_source_authentication_failure
            - source: (url1|url2)
            """
        ];

        yield return
        [
            // message
            new PrivateSourceBadResponse(["url1", "url2"]),
            // expected
            """
            Error type: private_source_bad_response
            - source: (url1|url2)
            """
        ];

        yield return
        [
            // message
            new PullRequestExistsForLatestVersion("Some.Dependency", "1.2.3"),
            // expected
            """
            Error type: pull_request_exists_for_latest_version
            - dependency-name: Some.Dependency
            - dependency-version: 1.2.3
            """
        ];

        yield return
        [
            // message
            new PullRequestExistsForSecurityUpdate([new("Some.Dependency", "1.2.3", DependencyType.PackageReference)]),
            // expected
            """
            Error type: pull_request_exists_for_security_update
            - updated-dependencies:
              - - dependency-name: Some.Dependency
                - dependency-version: 1.2.3
                - dependency-removed: false
            """
        ];

        yield return
        [
            // message
            new SecurityUpdateDependencyNotFound(),
            // expected
            """
            Error type: security_update_dependency_not_found
            """
        ];

        yield return
        [
            // message
            new SecurityUpdateIgnored("Some.Dependency"),
            // expected
            """
            Error type: all_versions_ignored
            - dependency-name: Some.Dependency
            """
        ];

        yield return
        [
            // message
            new SecurityUpdateNotFound("Some.Dependency", "1.2.3"),
            // expected
            """
            Error type: security_update_not_found
            - dependency-name: Some.Dependency
            - dependency-version: 1.2.3
            """
        ];

        yield return
        [
            // message
            new SecurityUpdateNotNeeded("Some.Dependency"),
            // expected
            """
            Error type: security_update_not_needed
            - dependency-name: Some.Dependency
            """
        ];

        yield return
        [
            // message
            new SecurityUpdateNotPossible("Some.Dependency", "1.2.3", "4.5.6", ["dep1", "dep2"]),
            // expected
            """
            Error type: security_update_not_possible
            - dependency-name: Some.Dependency
            - latest-resolvable-version: 1.2.3
            - lowest-non-vulnerable-version: 4.5.6
            - conflicting-dependencies:
              - dep1
              - dep2
            """
        ];

        yield return
        [
            // message
            new UnknownError(new NotImplementedException("error message"), "TEST-JOB-ID"),
            // expected
            """
            Error type: unknown_error
            - error-class: NotImplementedException
            - error-message: System.NotImplementedException: error message
            - package-manager: nuget
            - job-id: TEST-JOB-ID
            """
        ];

        yield return
        [
            // message
            new UpdateNotPossible(["Dependency1", "Dependency2"]),
            // expected
            """
            Error type: update_not_possible
            - dependencies:
              - Dependency1
              - Dependency2
            """
        ];

        yield return
        [
            // message
            new UpdatePullRequest()
            {
                DependencyNames = ["Dependency1", "Dependency2"],
                UpdatedDependencyFiles = [], // unused
                BaseCommitSha = "unused",
                CommitMessage = "unused",
                PrTitle = "unused",
                PrBody = "unused",
                DependencyGroup = "unused",
            },
            // expected
            """
            UpdatePullRequest
            - Dependency1
            - Dependency2
            """
        ];
    }
}
