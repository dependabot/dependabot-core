using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackageReferenceUpdaterTests
{
    [Theory]
    [MemberData(nameof(ComputeUpdateOperationsTestData))]
    public async Task ComputeUpdateOperations
    (
        ImmutableArray<Dependency> topLevelDependencies,
        ImmutableArray<Dependency> requestedUpdates,
        ImmutableArray<Dependency> resolvedDependencies,
        ImmutableArray<UpdateOperationBase> expectedUpdateOperations
    )
    {
        // arrange
        using var repoRoot = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", "<Project Sdk=\"Microsoft.NET.Sdk\" />"));
        var projectPath = Path.Combine(repoRoot.DirectoryPath, "project.csproj");
        var experimentsManager = new ExperimentsManager() { UseDirectDiscovery = true };
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory([
            MockNuGetPackage.CreateSimplePackage("Parent.Package", "1.0.0", "net9.0", [(null, [("Transitive.Package", "1.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Parent.Package", "2.0.0", "net9.0", [(null, [("Transitive.Package", "2.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Transitive.Package", "1.0.0", "net9.0", [(null, [("Super.Transitive.Package", "1.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Transitive.Package", "2.0.0", "net9.0", [(null, [("Super.Transitive.Package", "2.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Super.Transitive.Package", "1.0.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Super.Transitive.Package", "2.0.0", "net9.0")
        ], repoRoot.DirectoryPath);

        // act
        var actualUpdateOperations = await PackageReferenceUpdater.ComputeUpdateOperations(
            repoRoot.DirectoryPath,
            projectPath,
            "net9.0",
            topLevelDependencies,
            requestedUpdates,
            resolvedDependencies,
            experimentsManager,
            new TestLogger());

        // assert
        AssertEx.Equal(expectedUpdateOperations, actualUpdateOperations);
    }

    public static IEnumerable<object[]> ComputeUpdateOperationsTestData()
    {
        // single dependency update
        yield return
        [
            // topLevelDependencies
            ImmutableArray.Create(
                new Dependency("Some.Package", "1.0.0", DependencyType.PackageReference),
                new Dependency("Unrelated.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // requestedUpdates
            ImmutableArray.Create(
                new Dependency("Some.Package", "1.0.1", DependencyType.PackageReference)
            ),

            // resolvedDependencies
            ImmutableArray.Create(
                new Dependency("Some.Package", "1.0.1", DependencyType.PackageReference),
                new Dependency("Unrelated.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // expectedUpdateOperations
            ImmutableArray.Create<UpdateOperationBase>(
                new DirectUpdate()
                {
                    DependencyName = "Some.Package",
                    NewVersion = NuGetVersion.Parse("1.0.1"),
                    UpdatedFiles = [],
                }
            )
        ];

        // dependency was updated by pinning
        yield return
        [
            // topLevelDependencies
            ImmutableArray.Create(
                new Dependency("Top.Level.Package", "1.0.0", DependencyType.PackageReference)
            ),

            // requestedUpdates
            ImmutableArray.Create(
                new Dependency("Transitive.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // resolvedDependencies
            ImmutableArray.Create(
                new Dependency("Top.Level.Package", "1.0.0", DependencyType.PackageReference),
                new Dependency("Transitive.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // expectedUpdateOperations
            ImmutableArray.Create<UpdateOperationBase>(
                new PinnedUpdate()
                {
                    DependencyName = "Transitive.Package",
                    NewVersion = NuGetVersion.Parse("2.0.0"),
                    UpdatedFiles = [],
                }
            )
        ];

        // dependency was updated by updating parent 1 level up
        yield return
        [
            // topLevelDependencies
            ImmutableArray.Create(
                new Dependency("Parent.Package", "1.0.0", DependencyType.PackageReference)
            ),

            // requestedUpdates
            ImmutableArray.Create(
                new Dependency("Transitive.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // resolvedDependencies
            ImmutableArray.Create(
                new Dependency("Parent.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // expectedUpdateOperations
            ImmutableArray.Create<UpdateOperationBase>(
                new ParentUpdate()
                {
                    DependencyName = "Transitive.Package",
                    NewVersion = NuGetVersion.Parse("2.0.0"),
                    UpdatedFiles = [],
                    ParentDependencyName = "Parent.Package",
                    ParentNewVersion = NuGetVersion.Parse("2.0.0"),
                }
            )
        ];

        // dependency was updated by updating parent 2 levels up
        yield return
        [
            // topLevelDependencies
            ImmutableArray.Create(
                new Dependency("Parent.Package", "1.0.0", DependencyType.PackageReference)
            ),

            // requestedUpdates
            ImmutableArray.Create(
                new Dependency("Super.Transitive.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // resolvedDependencies
            ImmutableArray.Create(
                new Dependency("Parent.Package", "2.0.0", DependencyType.PackageReference)
            ),

            // expectedUpdateOperations
            ImmutableArray.Create<UpdateOperationBase>(
                new ParentUpdate()
                {
                    DependencyName = "Super.Transitive.Package",
                    NewVersion = NuGetVersion.Parse("2.0.0"),
                    UpdatedFiles = [],
                    ParentDependencyName = "Parent.Package",
                    ParentNewVersion = NuGetVersion.Parse("2.0.0"),
                }
            )
        ];
    }
}
