using System.Collections.Immutable;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

using DepType = NuGetUpdater.Core.Run.ApiModel.DependencyType;

namespace NuGetUpdater.Core.Test.Run;

public class UpdateAllowedTests
{
    [Theory]
    [MemberData(nameof(IsUpdateAllowedTestData))]
    public void IsUpdateAllowed(Job job, Dependency dependency, bool expectedResult)
    {
        var actualResult = RunWorker.IsUpdateAllowed(job, dependency);
        Assert.Equal(expectedResult, actualResult);
    }

    public static IEnumerable<object[]> IsUpdateAllowedTestData()
    {
        // with default allowed updates on a transitive dependency
        yield return
        [
            CreateJob(
                allowedUpdates: [
                    new AllowedUpdate() { DependencyType = DepType.Direct, UpdateType = UpdateType.All }
                ],
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: false),
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
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: true),
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
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true),
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
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("> 1.8.0")], PatchedVersions = [], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true),
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
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [Requirement.Parse("< 1.8.0"), Requirement.Parse("> 1.8.0")], PatchedVersions = [], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: true),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [],
                securityUpdatesOnly: false),
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
                securityAdvisories: [
                    new Advisory() { DependencyName = "Some.Package", AffectedVersions = [], PatchedVersions = [Requirement.Parse(">= 1.11.0")], UnaffectedVersions = [] }
                ],
                securityUpdatesOnly: false),
            new Dependency("Some.Package", "1.8.0", DependencyType.PackageReference, IsTransitive: false),
            // expectedResult
            true,
        ];
    }

    private static Job CreateJob(AllowedUpdate[] allowedUpdates, Advisory[] securityAdvisories, bool securityUpdatesOnly)
    {
        return new Job()
        {
            AllowedUpdates = allowedUpdates.ToImmutableArray(),
            SecurityAdvisories = securityAdvisories.ToImmutableArray(),
            SecurityUpdatesOnly = securityUpdatesOnly,
            Source = new()
            {
                Provider = "nuget",
                Repo = "test/repo",
            }
        };
    }
}
