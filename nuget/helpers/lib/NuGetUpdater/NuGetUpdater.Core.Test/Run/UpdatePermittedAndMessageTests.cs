using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

using DepType = NuGetUpdater.Core.Run.ApiModel.DependencyType;

namespace NuGetUpdater.Core.Test.Run;

public class UpdatePermittedAndMessageTests
{
    [Theory]
    [MemberData(nameof(UpdatePermittedAndMessageTestData))]
    public void UpdatePermittedAndMessage(Job job, Dependency dependency, bool expectedResult, MessageBase? expectedMessage)
    {
        var (actualResult, actualMessage) = RunWorker.UpdatePermittedAndMessage(job, dependency);
        Assert.Equal(expectedResult, actualResult);

        if (expectedMessage is null)
        {
            Assert.Null(actualMessage);
        }
        else
        {
            Assert.True(actualMessage is not null, $"Expected message of type {expectedMessage.GetType().Name} but got null");
            Assert.Equal(expectedMessage.GetType(), actualMessage.GetType());
            var actualMessageJson = HttpApiHandler.Serialize(actualMessage);
            var expectedMessageJson = HttpApiHandler.Serialize(expectedMessage);
            Assert.Equal(expectedMessageJson, actualMessageJson);
        }
    }

    public static IEnumerable<object?[]> UpdatePermittedAndMessageTestData()
    {
        // with default allowed updates on a transitive dependency
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: true),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // when dealing with a security update
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: true),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // with a top-level dependency
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // with a sub-dependency
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: true),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // when insecure
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: true),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // when only security fixes are allowed
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // when dealing with a security fix
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // when dealing with a security fix that doesn't apply
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("> 1.8.0")], PatchedVersions = [], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            false,
            // expectedMessage
            new SecurityUpdateNotNeeded("Some.Package"),
        ];

        // when dealing with a security fix that doesn't apply to some versions
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All },
                    new AllowedUpdate() { DependencyType = DepType.Indirect, UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("< 1.8.0"), Requirement.Parse("> 1.8.0")], PatchedVersions = [], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.1", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // when a dependency allow list that includes the dependency
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Some.Package" }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // with a dependency allow list that uses a wildcard
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Some.*" }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // when dependency allow list that excludes the dependency
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Unrelated.Package" }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // when matching with an incomplete dependency name
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Some" }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // with a dependency allow list that uses a wildcard
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Unrelated.*" }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // when security fixes are also allowed
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Unrelated.Package" },
                    new AllowedUpdate() { UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            false,
            // expectedMessage
            null,
        ];

        // when dealing with a security fix
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyName = "Unrelated.Package"}, new AllowedUpdate(){ UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
            // expectedMessage
            null,
        ];

        // security job, not vulnerable => security update not needed
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("1.0.0")], PatchedVersions = [Requirement.Parse("1.1.0")] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.1.0", DependencyType.PackageReference),
            // expectedResult
            false,
            // expectedMessage
            new SecurityUpdateNotNeeded("Some.Package")
        ];

        // security job, not updating existing => pr already exists
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { UpdateType = UpdateType.Security }
                ],
                dependencies: [],
                existingPrs: [
                    new PullRequest() { Dependencies = [new PullRequestDependency() { DependencyName = "Some.Package", DependencyVersion = NuGetVersion.Parse("1.2.0") }] }
                ],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("1.1.0")] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new Dependency("Some.Package", "1.1.0", DependencyType.PackageReference),
            // expectedResult
            false,
            // expectedMessage
            new PullRequestExistsForLatestVersion("Some.Package", "1.2.0")
        ];

        // security job, updating existing => do update
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { UpdateType = UpdateType.All, DependencyType = DepType.Direct }
                ],
                dependencies: ["Some.Package"],
                existingPrs: [
                    new PullRequest() { Dependencies = [new PullRequestDependency() { DependencyName = "Some.Package", DependencyVersion = NuGetVersion.Parse("1.1.0") }] }
                ],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse(">= 1.0.0, < 1.1.0")] }
                ],
                securityUpdatesOnly: true,
                updatingAPullRequest: true),
            new Dependency("Some.Package", "1.0.0", DependencyType.PackageReference),
            // expectedResult
            true,
            // expectedMessage
            null
        ];
    }

    private static Job CreateJob(
        ImmutableArray<AllowedUpdate> allowedUpdates,
        ImmutableArray<string> dependencies,
        ImmutableArray<PullRequest> existingPrs,
        ImmutableArray<Advisory> securityAdvisories,
        bool securityUpdatesOnly,
        bool updatingAPullRequest)
    {
        return new Job()
        {
            AllowedUpdates = allowedUpdates,
            Dependencies = dependencies,
            ExistingPullRequests = existingPrs,
            SecurityAdvisories = securityAdvisories,
            SecurityUpdatesOnly = securityUpdatesOnly,
            Source = new()
            {
                Provider = "nuget",
                Repo = "test/repo",
            },
            UpdatingAPullRequest = updatingAPullRequest,
        };
    }
}
