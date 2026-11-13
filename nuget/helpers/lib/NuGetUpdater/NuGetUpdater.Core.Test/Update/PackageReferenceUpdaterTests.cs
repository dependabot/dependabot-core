using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackageReferenceUpdaterTests
{
    [Fact]
    public void BuildReverseGraph_ReturnsCorrectParents()
    {
        // arrange
        var dependencyGraph = new Dictionary<string, ImmutableArray<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["Parent.Package/1.0.0"] = ["Transitive.Package/2.0.0"],
            ["Transitive.Package/2.0.0"] = ["Super.Transitive.Package/3.0.0"],
            ["Super.Transitive.Package/3.0.0"] = [],
        }.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase);

        // act
        var packageParents = PackageReferenceUpdater.BuildReverseGraph(dependencyGraph, new TestLogger());

        // assert
        Assert.Equal("Parent.Package", packageParents["Transitive.Package"].Single());
        Assert.Equal("Transitive.Package", packageParents["Super.Transitive.Package"].Single());
    }

    [Fact]
    public void BuildReverseGraph_HandlesMultipleVersionsOfSamePackage()
    {
        // arrange - simulates a merged graph where the same package appears at different versions
        var dependencyGraph = new Dictionary<string, ImmutableArray<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["Parent.Package/1.0.0"] = ["Child.Package/1.0.0"],
            ["Parent.Package/2.0.0"] = ["Child.Package/2.0.0"],
            ["Child.Package/1.0.0"] = [],
            ["Child.Package/2.0.0"] = [],
        }.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase);

        // act
        var packageParents = PackageReferenceUpdater.BuildReverseGraph(dependencyGraph, new TestLogger());

        // assert - both version entries contribute the same parent name
        Assert.Equal("Parent.Package", packageParents["Child.Package"].Single());
    }

    [Theory]
    [MemberData(nameof(ComputeUpdateOperationsTestData))]
    public void ComputeUpdateOperations
    (
        ImmutableArray<Dependency> topLevelDependencies,
        ImmutableArray<Dependency> requestedUpdates,
        ImmutableArray<Dependency> resolvedDependencies,
        ImmutableDictionary<string, ImmutableArray<string>> dependencyGraph,
        ImmutableArray<UpdateOperationBase> expectedUpdateOperations
    )
    {
        // act
        var actualUpdateOperations = PackageReferenceUpdater.ComputeUpdateOperations(
            topLevelDependencies,
            requestedUpdates,
            resolvedDependencies,
            dependencyGraph,
            new TestLogger());

        // assert
        AssertEx.Equal(expectedUpdateOperations, actualUpdateOperations);
    }

    /// <summary>
    /// A dependency graph representing:
    ///   Parent.Package/2.0.0 -> Transitive.Package/2.0.0 -> Super.Transitive.Package/2.0.0
    /// </summary>
    private static readonly ImmutableDictionary<string, ImmutableArray<string>> TestDependencyGraph =
        new Dictionary<string, ImmutableArray<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["Parent.Package/2.0.0"] = ["Transitive.Package/2.0.0"],
            ["Transitive.Package/2.0.0"] = ["Super.Transitive.Package/2.0.0"],
            ["Super.Transitive.Package/2.0.0"] = [],
        }.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase);

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

            // dependencyGraph
            new Dictionary<string, ImmutableArray<string>>(StringComparer.OrdinalIgnoreCase)
            {
                ["Some.Package/1.0.1"] = [],
                ["Unrelated.Package/2.0.0"] = [],
            }.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase),

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

            // dependencyGraph
            new Dictionary<string, ImmutableArray<string>>(StringComparer.OrdinalIgnoreCase)
            {
                ["Top.Level.Package/1.0.0"] = ["Transitive.Package/2.0.0"],
                ["Transitive.Package/2.0.0"] = [],
            }.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase),

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

            // dependencyGraph
            TestDependencyGraph,

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

            // dependencyGraph
            TestDependencyGraph,

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

        // dependency was not updated
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
                new Dependency("Parent.Package", "1.0.0", DependencyType.PackageReference)
            ),
            // dependencyGraph
            new Dictionary<string, ImmutableArray<string>>(StringComparer.OrdinalIgnoreCase)
            {
                ["Parent.Package/1.0.0"] = ["Transitive.Package/1.0.0"],
                ["Transitive.Package/1.0.0"] = [],
            }.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase),
            // expectedUpdateOperations
            ImmutableArray<UpdateOperationBase>.Empty,
        ];

        // initial dependency has a wildcard
        yield return
        [
            // topLevelDependencies
            ImmutableArray.Create(
                new Dependency("Parent.Package", "1.0.0", DependencyType.PackageReference),
                new Dependency("Unrelated.Package", "1.0.*", DependencyType.PackageReference)
            ),
            // requestedUpdates
            ImmutableArray.Create(
                new Dependency("Transitive.Package", "2.0.0", DependencyType.PackageReference)
            ),
            // resolvedDependencies
            ImmutableArray.Create(
                new Dependency("Parent.Package", "2.0.0", DependencyType.PackageReference),
                new Dependency("Unrelated.Package", "1.0.0", DependencyType.PackageReference)
            ),
            // dependencyGraph
            TestDependencyGraph,
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
            ),
        ];
    }
}
