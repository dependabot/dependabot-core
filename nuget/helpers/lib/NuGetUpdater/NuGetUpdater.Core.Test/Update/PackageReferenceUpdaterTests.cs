using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackageReferenceUpdaterTests
{
    [Fact]
    public async Task DirectBuildFileChangesAreMaintainedWhenPinningTransitiveDependency()
    {
        // arrange
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync([("project.csproj", """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net9.0</TargetFramework>
              </PropertyGroup>
              <ItemGroup>
                <PackageReference Include="Completely.Different.Package" Version="1.0.0" />
                <PackageReference Include="Some.Package" Version="1.0.0" />
              </ItemGroup>
            </Project>
            """)]);
        var packages = new[]
        {
            MockNuGetPackage.CreateSimplePackage("Completely.Different.Package", "1.0.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Completely.Different.Package", "2.0.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net9.0", [(null, [("Transitive.Package", "1.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Transitive.Package", "1.0.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Transitive.Package", "2.0.0", "net9.0"),
        };
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDir.DirectoryPath);
        var fullProjectPath = Path.Combine(tempDir.DirectoryPath, "project.csproj");
        var buildFile = ProjectBuildFile.Open(tempDir.DirectoryPath, fullProjectPath);
        var experimentsManager = new ExperimentsManager();

        // act
        // pin transitive dependency
        var updatedFiles = await PackageReferenceUpdater.UpdateTransitiveDependencyAsync(
            tempDir.DirectoryPath,
            fullProjectPath,
            "Transitive.Package",
            "2.0.0",
            [buildFile],
            experimentsManager,
            new TestLogger());

        // subsequent update should not overwrite previous change
        PackageReferenceUpdater.TryUpdateDependencyVersion([buildFile], "Completely.Different.Package", "1.0.0", "2.0.0", new TestLogger());

        // assert
        await buildFile.SaveAsync();
        var actualContents = await File.ReadAllTextAsync(fullProjectPath, TestContext.Current.CancellationToken);
        var expectedContents = """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net9.0</TargetFramework>
              </PropertyGroup>
              <ItemGroup>
                <PackageReference Include="Completely.Different.Package" Version="2.0.0" />
                <PackageReference Include="Some.Package" Version="1.0.0" />
                <PackageReference Include="Transitive.Package" Version="2.0.0" />
              </ItemGroup>
            </Project>
            """;
        Assert.Equal(expectedContents, actualContents);
    }

    [Fact]
    public async Task DirectBuildFileChangesAreMaintainedWhenPinningTransitiveDependency_DirectoryPackagesPropsIsDiscovered()
    {
        // arrange
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
        [
            ("project.csproj", """
                 <Project Sdk="Microsoft.NET.Sdk">
                   <PropertyGroup>
                     <TargetFramework>net9.0</TargetFramework>
                   </PropertyGroup>
                   <ItemGroup>
                     <PackageReference Include="Completely.Different.Package" />
                     <PackageReference Include="Some.Package" />
                   </ItemGroup>
                 </Project>
                 """),
            ("Directory.Packages.props", """
                <Project>
                  <PropertyGroup>
                    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageVersion Include="Completely.Different.Package" Version="1.0.0" />
                    <PackageVersion Include="Some.Package" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """)
        ]);
        var packages = new[]
        {
             MockNuGetPackage.CreateSimplePackage("Completely.Different.Package", "1.0.0", "net9.0"),
             MockNuGetPackage.CreateSimplePackage("Completely.Different.Package", "2.0.0", "net9.0"),
             MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net9.0", [(null, [("Transitive.Package", "1.0.0")])]),
             MockNuGetPackage.CreateSimplePackage("Transitive.Package", "1.0.0", "net9.0"),
             MockNuGetPackage.CreateSimplePackage("Transitive.Package", "2.0.0", "net9.0"),
         };
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDir.DirectoryPath);
        var fullProjectPath = Path.Combine(tempDir.DirectoryPath, "project.csproj");
        var fullDirectoryPackagesPath = Path.Combine(tempDir.DirectoryPath, "Directory.Packages.props");
        var buildFiles = new[]
        {
            ProjectBuildFile.Open(tempDir.DirectoryPath, fullProjectPath),
            ProjectBuildFile.Open(tempDir.DirectoryPath, fullDirectoryPackagesPath)
        }.ToImmutableArray();
        var experimentsManager = new ExperimentsManager();

        // act
        // pin transitive dependency
        var updatedFiles = await PackageReferenceUpdater.UpdateTransitiveDependencyAsync(
            tempDir.DirectoryPath,
            fullProjectPath,
            "Transitive.Package",
            "2.0.0",
            buildFiles,
            experimentsManager,
            new TestLogger());

        // subsequent update should not overwrite previous change
        PackageReferenceUpdater.TryUpdateDependencyVersion(buildFiles, "Completely.Different.Package", "1.0.0", "2.0.0", new TestLogger());

        // assert
        foreach (var bf in buildFiles)
        {
            await bf.SaveAsync();
        }

        var actualProjectContents = await File.ReadAllTextAsync(fullProjectPath, TestContext.Current.CancellationToken);
        var expectedProjectContents = """
             <Project Sdk="Microsoft.NET.Sdk">
               <PropertyGroup>
                 <TargetFramework>net9.0</TargetFramework>
               </PropertyGroup>
               <ItemGroup>
                 <PackageReference Include="Completely.Different.Package" />
                 <PackageReference Include="Some.Package" />
                 <PackageReference Include="Transitive.Package" />
               </ItemGroup>
             </Project>
             """;
        Assert.Equal(expectedProjectContents.Replace("\r", ""), actualProjectContents.Replace("\r", ""));

        var actualDirectoryPackagesContents = await File.ReadAllTextAsync(fullDirectoryPackagesPath, TestContext.Current.CancellationToken);
        var expectedDirectoryPackagesContents = """
            <Project>
              <PropertyGroup>
                <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
              </PropertyGroup>
              <ItemGroup>
                <PackageVersion Include="Completely.Different.Package" Version="2.0.0" />
                <PackageVersion Include="Some.Package" Version="1.0.0" />
                <PackageVersion Include="Transitive.Package" Version="2.0.0" />
              </ItemGroup>
            </Project>
            """;
        Assert.Equal(expectedDirectoryPackagesContents.Replace("\r", ""), actualDirectoryPackagesContents.Replace("\r", ""));
    }

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
            MockNuGetPackage.CreateSimplePackage("Super.Transitive.Package", "2.0.0", "net9.0"),
            MockNuGetPackage.CreateSimplePackage("Unrelated.Package", "1.0.0", "net9.0"),
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
