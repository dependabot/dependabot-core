using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

using DepType = NuGetUpdater.Core.Run.ApiModel.DependencyType;

namespace NuGetUpdater.Core.Test.Run.ApiModel;

public class JobTests
{
    [Theory]
    [MemberData(nameof(IsUpdatePermittedTestData))]
    public void IsUpdatePermitted(Job job, Dependency dependency, bool expectedResult)
    {
        var actualResult = job.IsUpdatePermitted(dependency);
        Assert.Equal(expectedResult, actualResult);
    }

    public static IEnumerable<object?[]> IsUpdatePermittedTestData()
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
