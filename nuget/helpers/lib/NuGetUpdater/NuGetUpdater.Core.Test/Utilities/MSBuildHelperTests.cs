using System.Collections.Immutable;

using NuGet.Build.Tasks;

using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

using TestFile = (string Path, string Content);

public class MSBuildHelperTests : TestBase
{
    [Fact]
    public void GetRootedValue_FindsValue()
    {
        // Arrange
        var projectContents = """
            <Project>
                <PropertyGroup>
                    <TargetFramework>net8.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                    <PackageReference Include="Some.Package" Version="$(PackageVersion1)" />
                </ItemGroup>
            </Project>
            """;
        var propertyInfo = new Dictionary<string, Property>
        {
            { "PackageVersion1", new("PackageVersion1", "1.1.1", "Packages.props") },
        };

        // Act
        var (resultType, _, evaluatedValue, _, _) = MSBuildHelper.GetEvaluatedValue(projectContents, propertyInfo);

        Assert.Equal(EvaluationResultType.Success, resultType);

        // Assert
        Assert.Equal("""
            <Project>
                <PropertyGroup>
                    <TargetFramework>net8.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                    <PackageReference Include="Some.Package" Version="1.1.1" />
                </ItemGroup>
            </Project>
            """, evaluatedValue);
    }

    [Fact(Timeout = 1000)]
    public async Task GetRootedValue_DoesNotRecurseAsync()
    {
        // Arrange
        var projectContents = """
            <Project>
                <PropertyGroup>
                    <TargetFramework>net8.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                    <PackageReference Include="Some.Package" Version="$(PackageVersion1)" />
                </ItemGroup>
            </Project>
            """;
        var propertyInfo = new Dictionary<string, Property>
        {
            { "PackageVersion1", new("PackageVersion1", "$(PackageVersion2)", "Packages.props") },
            { "PackageVersion2", new("PackageVersion2", "$(PackageVersion1)", "Packages.props") }
        };
        // This is needed to make the timeout work. Without that we could get caugth in an infinite loop.
        await Task.Delay(1);

        // Act
        var (resultType, _, _, _, errorMessage) = MSBuildHelper.GetEvaluatedValue(projectContents, propertyInfo);

        // Assert
        Assert.Equal(EvaluationResultType.CircularReference, resultType);
        Assert.Equal("Property 'PackageVersion1' has a circular reference.", errorMessage);
    }

    [Theory]
    [MemberData(nameof(SolutionProjectPathTestData))]
    public void ProjectPathsCanBeParsedFromSolutionFiles(string solutionContent, string[] expectedProjectSubPaths)
    {
        var solutionPath = Path.GetTempFileName();
        var solutionDirectory = Path.GetDirectoryName(solutionPath)!;
        try
        {
            File.WriteAllText(solutionPath, solutionContent);
            var actualProjectSubPaths = MSBuildHelper.GetProjectPathsFromSolution(solutionPath).ToArray();
            var expectedPaths = expectedProjectSubPaths.Select(path => Path.Combine(solutionDirectory, path)).ToArray();
            if (Environment.OSVersion.Platform == PlatformID.Win32NT)
            {
                // make the test happy when running on Windows
                expectedPaths = expectedPaths.Select(p => p.Replace("/", "\\")).ToArray();
            }

            AssertEx.Equal(expectedPaths, actualProjectSubPaths);
        }
        finally
        {
            File.Delete(solutionPath);
        }
    }

    [Theory]
    [InlineData("<Project><PropertyGroup><TargetFramework>netstandard2.0</TargetFramework></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>netstandard2.0</TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>  ; netstandard2.0 ; </TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFrameworks>netstandard2.0 ; netstandard2.1 ; </TargetFrameworks></PropertyGroup></Project>", "netstandard2.0", "netstandard2.1")]
    [InlineData("<Project><PropertyGroup><TargetFramework>netstandard2.0</TargetFramework><TargetFrameworkVersion Condition='False'>v4.7.2</TargetFrameworkVersion></PropertyGroup></Project>", "netstandard2.0", null)]
    [InlineData("<Project><PropertyGroup><TargetFramework>$(PropertyThatCannotBeResolved)</TargetFramework></PropertyGroup></Project>", null, null)]
    public async Task TfmsCanBeDeterminedFromProjectContents(string projectContents, string? expectedTfm1, string? expectedTfm2)
    {
        var projectPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(projectPath, projectContents);
            var expectedTfms = new[] { expectedTfm1, expectedTfm2 }.Where(tfm => tfm is not null).ToArray();
            var (_buildFiles, actualTfms) = await MSBuildHelper.LoadBuildFilesAndTargetFrameworksAsync(Path.GetDirectoryName(projectPath)!, projectPath);
            AssertEx.Equal(expectedTfms, actualTfms);
        }
        finally
        {
            File.Delete(projectPath);
        }
    }

    [Theory]
    [MemberData(nameof(GetTopLevelPackageDependencyInfosTestData))]
    public async Task TopLevelPackageDependenciesCanBeDetermined(TestFile[] buildFileContents, Dependency[] expectedTopLevelDependencies, MockNuGetPackage[] testPackages)
    {
        using var testDirectory = new TemporaryDirectory();
        var buildFiles = new List<ProjectBuildFile>();

        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(testPackages, testDirectory.DirectoryPath);

        foreach (var (path, content) in buildFileContents)
        {
            var fullPath = Path.Combine(testDirectory.DirectoryPath, path);
            await File.WriteAllTextAsync(fullPath, content);
            buildFiles.Add(ProjectBuildFile.Parse(testDirectory.DirectoryPath, fullPath, content));
        }

        var actualTopLevelDependencies = MSBuildHelper.GetTopLevelPackageDependencyInfos(buildFiles.ToImmutableArray());
        AssertEx.Equal(expectedTopLevelDependencies, actualTopLevelDependencies);
    }

    [Fact]
    public async Task AllPackageDependenciesCanBeTraversed()
    {
        using var temp = new TemporaryDirectory();
        MockNuGetPackage[] testPackages =
        [
            MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "netstandard2.0", [(null, [("Package.B", "2.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "netstandard2.0", [(null, [("Package.C", "3.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.C", "3.0.0", "netstandard2.0", [(null, [("Package.D", "4.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.D", "4.0.0", "netstandard2.0"),
        ];
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(testPackages, temp.DirectoryPath);

        Dependency[] expectedDependencies =
        [
            new("NETStandard.Library", "2.0.3", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Package.A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Package.C", "3.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Package.D", "4.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
        ];
        Dependency[] actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "netstandard2.0",
            [new Dependency("Package.A", "1.0.0", DependencyType.Unknown)]
        );
        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Fact]
    public async Task AllPackageDependencies_DoNotTruncateLongDependencyLists()
    {
        using var temp = new TemporaryDirectory();
        MockNuGetPackage[] testPackages =
        [
            MockNuGetPackage.CreateSimplePackage("Package.1A", "1.0.0", "net8.0", [(null, [("Package.1B", "2.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1B", "2.0.0", "net8.0", [(null, [("Package.1C", "3.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1C", "3.0.0", "net8.0", [(null, [("Package.1D", "4.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1D", "4.0.0", "net8.0", [(null, [("Package.1E", "5.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1E", "5.0.0", "net8.0", [(null, [("Package.1F", "6.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1F", "6.0.0", "net8.0", [(null, [("Package.1G", "7.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1G", "7.0.0", "net8.0", [(null, [("Package.1H", "8.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1H", "8.0.0", "net8.0", [(null, [("Package.1I", "9.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1I", "9.0.0", "net8.0", [(null, [("Package.1J", "10.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1J", "10.0.0", "net8.0", [(null, [("Package.1K", "11.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1K", "11.0.0", "net8.0", [(null, [("Package.1L", "12.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1L", "12.0.0", "net8.0", [(null, [("Package.1M", "13.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1M", "13.0.0", "net8.0", [(null, [("Package.1N", "14.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1N", "14.0.0", "net8.0", [(null, [("Package.1O", "15.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1O", "15.0.0", "net8.0", [(null, [("Package.1P", "16.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1P", "16.0.0", "net8.0", [(null, [("Package.1Q", "17.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1Q", "17.0.0", "net8.0", [(null, [("Package.1R", "18.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1R", "18.0.0", "net8.0", [(null, [("Package.1S", "19.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1S", "19.0.0", "net8.0", [(null, [("Package.1T", "20.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1T", "20.0.0", "net8.0", [(null, [("Package.1U", "21.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1U", "21.0.0", "net8.0", [(null, [("Package.1V", "22.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1V", "22.0.0", "net8.0", [(null, [("Package.1W", "23.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1W", "23.0.0", "net8.0", [(null, [("Package.1X", "24.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1X", "24.0.0", "net8.0", [(null, [("Package.1Y", "25.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1Y", "25.0.0", "net8.0", [(null, [("Package.1Z", "26.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.1Z", "26.0.0", "net8.0", [(null, [("Package.2A", "1.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2A", "1.0.0", "net8.0", [(null, [("Package.2B", "2.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2B", "2.0.0", "net8.0", [(null, [("Package.2C", "3.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2C", "3.0.0", "net8.0", [(null, [("Package.2D", "4.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2D", "4.0.0", "net8.0", [(null, [("Package.2E", "5.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2E", "5.0.0", "net8.0", [(null, [("Package.2F", "6.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2F", "6.0.0", "net8.0", [(null, [("Package.2G", "7.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2G", "7.0.0", "net8.0", [(null, [("Package.2H", "8.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2H", "8.0.0", "net8.0", [(null, [("Package.2I", "9.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2I", "9.0.0", "net8.0", [(null, [("Package.2J", "10.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2J", "10.0.0", "net8.0", [(null, [("Package.2K", "11.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2K", "11.0.0", "net8.0", [(null, [("Package.2L", "12.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2L", "12.0.0", "net8.0", [(null, [("Package.2M", "13.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2M", "13.0.0", "net8.0", [(null, [("Package.2N", "14.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2N", "14.0.0", "net8.0", [(null, [("Package.2O", "15.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2O", "15.0.0", "net8.0", [(null, [("Package.2P", "16.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2P", "16.0.0", "net8.0", [(null, [("Package.2Q", "17.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2Q", "17.0.0", "net8.0", [(null, [("Package.2R", "18.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2R", "18.0.0", "net8.0", [(null, [("Package.2S", "19.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2S", "19.0.0", "net8.0", [(null, [("Package.2T", "20.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2T", "20.0.0", "net8.0", [(null, [("Package.2U", "21.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2U", "21.0.0", "net8.0", [(null, [("Package.2V", "22.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2V", "22.0.0", "net8.0", [(null, [("Package.2W", "23.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2W", "23.0.0", "net8.0", [(null, [("Package.2X", "24.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2X", "24.0.0", "net8.0", [(null, [("Package.2Y", "25.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2Y", "25.0.0", "net8.0", [(null, [("Package.2Z", "26.0.0")])]),
            MockNuGetPackage.CreateSimplePackage("Package.2Z", "26.0.0", "net8.0"),
        ];
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(testPackages, temp.DirectoryPath);

        Dependency[] expectedDependencies =
        [
            new("Package.1A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new("Package.1B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1C", "3.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1D", "4.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1E", "5.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1F", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1G", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1H", "8.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1I", "9.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1J", "10.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1K", "11.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1L", "12.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1M", "13.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1N", "14.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1O", "15.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1P", "16.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1Q", "17.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1R", "18.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new("Package.1S", "19.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1T", "20.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1U", "21.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1V", "22.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1W", "23.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1X", "24.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1Y", "25.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1Z", "26.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new("Package.2B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2C", "3.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2D", "4.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2E", "5.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2F", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2G", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2H", "8.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2I", "9.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2J", "10.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2K", "11.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2L", "12.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2M", "13.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2N", "14.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2O", "15.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2P", "16.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2Q", "17.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2R", "18.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new("Package.2S", "19.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2T", "20.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2U", "21.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2V", "22.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2W", "23.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2X", "24.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2Y", "25.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2Z", "26.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
        ];
        var packages = new[]
        {
            new Dependency("Package.1A", "1.0.0", DependencyType.Unknown),
            new Dependency("Package.1R", "18.0.0", DependencyType.Unknown),
            new Dependency("Package.2A", "1.0.0", DependencyType.Unknown),
            new Dependency("Package.2R", "18.0.0", DependencyType.Unknown),
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, temp.DirectoryPath, "net8.0", packages);
        for (int i = 0; i < actualDependencies.Length; i++)
        {
            var ad = actualDependencies[i];
            var ed = expectedDependencies[i];
            Assert.Equal(ed, ad);
        }

        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Fact]
    public async Task AllPackageDependencies_DoNotIncludeUpdateOnlyPackages()
    {
        using var temp = new TemporaryDirectory();
        MockNuGetPackage[] testPackages =
        [
            MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net8.0"),
            MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net8.0"),
            MockNuGetPackage.CreateSimplePackage("Package.C", "3.0.0", "net8.0"),
        ];
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(testPackages, temp.DirectoryPath);

        Dependency[] expectedDependencies =
        [
            new("Package.A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
        ];
        var packages = new[]
        {
            new Dependency("Package.A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new Dependency("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new Dependency("Package.C", "3.0.0", DependencyType.Unknown, IsUpdate: true)
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, temp.DirectoryPath, "net8.0", packages);
        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Fact]
    public async Task GetAllPackageDependencies_NugetConfigInvalid_DoesNotThrow()
    {
        var nugetPackagesDirectory = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        var nugetHttpCacheDirectory = Environment.GetEnvironmentVariable("NUGET_HTTP_CACHE_PATH");

        try
        {
            using var temp = new TemporaryDirectory();

            // It is important to have empty NuGet caches for this test, so override them with temp directories.
            var tempNuGetPackagesDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "packages");
            Environment.SetEnvironmentVariable("NUGET_PACKAGES", tempNuGetPackagesDirectory);
            var tempNuGetHttpCacheDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "v3-cache");
            Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", tempNuGetHttpCacheDirectory);

            // Write the NuGet.config with a missing "/>"
            await File.WriteAllTextAsync(
                Path.Combine(temp.DirectoryPath, "NuGet.Config"), """
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="contoso" value="https://contoso.com/v3/index.json"
                  </packageSources>
                </configuration>
                """);

            // Asserting it didn't throw
            var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                temp.DirectoryPath,
                temp.DirectoryPath,
                "net8.0",
                [new Dependency("Some.Package", "4.5.11", DependencyType.Unknown)]
            );
        }
        finally
        {
            // Restore the NuGet caches.
            Environment.SetEnvironmentVariable("NUGET_PACKAGES", nugetPackagesDirectory);
            Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", nugetHttpCacheDirectory);
        }
    }

    [Fact]
    public async Task AllPackageDependenciesCanBeFoundWithNuGetConfig()
    {
        var nugetPackagesDirectory = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        var nugetHttpCacheDirectory = Environment.GetEnvironmentVariable("NUGET_HTTP_CACHE_PATH");

        try
        {
            using var temp = new TemporaryDirectory();

            // It is important to have empty NuGet caches for this test, so override them with temp directories.
            var tempNuGetPackagesDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "packages");
            Environment.SetEnvironmentVariable("NUGET_PACKAGES", tempNuGetPackagesDirectory);
            var tempNuGetHttpCacheDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "v3-cache");
            Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", tempNuGetHttpCacheDirectory);

            // create two local package sources with different packages available in each
            string localSource1 = Path.Combine(temp.DirectoryPath, "localSource1");
            Directory.CreateDirectory(localSource1);
            string localSource2 = Path.Combine(temp.DirectoryPath, "localSource2");
            Directory.CreateDirectory(localSource2);

            // `Package.A` will only live in `localSource1` and will have a dependency on `Package.B` which is only
            // available in `localSource2`
            MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net8.0", [(null, [("Package.B", "2.0.0")])]).WriteToDirectory(localSource1);
            MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net8.0").WriteToDirectory(localSource2);
            await File.WriteAllTextAsync(Path.Join(temp.DirectoryPath, "NuGet.Config"), """
                <configuration>
                  <packageSources>
                    <add key="localSource1" value="./localSource1" />
                    <add key="localSource2" value="./localSource2" />
                  </packageSources>
                </configuration>
                """);

            Dependency[] expectedDependencies =
            [
                new("Package.A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                new("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            ];

            Dependency[] actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                temp.DirectoryPath,
                temp.DirectoryPath,
                "net8.0",
                [new Dependency("Package.A", "1.0.0", DependencyType.Unknown)]
            );

            AssertEx.Equal(expectedDependencies, actualDependencies);
        }
        finally
        {
            // Restore the NuGet caches.
            Environment.SetEnvironmentVariable("NUGET_PACKAGES", nugetPackagesDirectory);
            Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", nugetHttpCacheDirectory);
        }
    }

    [Fact]
    public async Task DependencyConflictsCanBeResolved()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolved)}_");
        MockNuGetPackage[] testPackages =
        [
            // some base packages
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"),
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.0", "net8.0"),
            // some packages that are hard-locked to specific versions of the previous package
            MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.0.0", "net8.0", [(null, [("Some.Package", "[1.0.0]")])]),
            MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.1.0", "net8.0", [(null, [("Some.Package", "[1.1.0]")])]),
            MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.2.0", "net8.0", [(null, [("Some.Package", "[1.2.0]")])]),
        ];
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(testPackages, repoRoot.FullName);

        // the package `Some.Package` was already updated from 1.0.0 to 1.2.0, but this causes a conflict with
        // `Some.Other.Package` that needs to be resolved
        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");
            await File.WriteAllTextAsync(projectPath, """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net8.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Package" Version="1.2.0" />
                    <PackageReference Include="Some.Other.Package" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """);
            var dependencies = new[]
            {
                new Dependency("Some.Package", "1.2.0", DependencyType.PackageReference),
                new Dependency("Some.Other.Package", "1.0.0", DependencyType.PackageReference),
            };
            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflicts(repoRoot.FullName, projectPath, "net8.0", dependencies, null, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(2, resolvedDependencies.Length);
            Assert.Equal("Some.Package", resolvedDependencies[0].Name);
            Assert.Equal("1.2.0", resolvedDependencies[0].Version);
            Assert.Equal("Some.Other.Package", resolvedDependencies[1].Name);
            Assert.Equal("1.2.0", resolvedDependencies[1].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 1
    // Singular Transitive Dependency with one root package, updating the root
    // Updating CS - Script Code to 2.0.0 reqires Microsoft.CodeAnalysis.CSharp.Scripting to be 3.6.0 and then Microsoft.CodeAnalysis.Common to be 3.6.0
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingTopLevelPackage()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewUpdatingTopLevelPackage)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");
            
            var dependencies = new[]
            {
                new Dependency("CS-Script.Core", "1.3.1", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.Common", "3.4.0", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.Scripting.Common", "3.4.0", DependencyType.PackageReference),
            };
            var update = new[]
            {
                new Dependency("CS-Script.Core", "2.0.0", DependencyType.PackageReference),
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(3, resolvedDependencies.Length);
            Assert.Equal("CS-Script.Core", resolvedDependencies[0].Name);
            Assert.Equal("2.0.0", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.Common", resolvedDependencies[1].Name);
            Assert.Equal("3.6.0", resolvedDependencies[1].Version);
            Assert.Equal("Microsoft.CodeAnalysis.Scripting.Common", resolvedDependencies[2].Name);
            Assert.Equal("3.6.0", resolvedDependencies[2].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 2
    // Updating a non-included dependency of an existing package to a new version, but the dependency is not in the existing package
    // Updating the dependency will require the existing top level package to also update
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingNonExistingDependency()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewUpdatingNonExistingDependency)}_");
        
        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("Azure.Core", "1.21.0", DependencyType.PackageReference)
            };
            var update = new[]
            {
                new Dependency("System.Text.Json", "4.7.2", DependencyType.Unknown)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(2, resolvedDependencies.Length);
            Assert.Equal("Azure.Core", resolvedDependencies[0].Name);
            Assert.Equal("1.21.0", resolvedDependencies[0].Version);
            Assert.Equal("System.Text.Json", resolvedDependencies[1].Name);
            Assert.Equal("4.7.2", resolvedDependencies[1].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 3, Another instance of scenario 2
    // Newtonsoft.Json needs to update to 13.0.1, although Newtonsoft.Json.Bson can use the original version of 12.0.1, for security vulernabilities and
    // adapatability, though NewtonsoftJson is not in the existing packages, it would be added to the existing list
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingAndKeepingDependency()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewUpdatingAndKeepingDependency)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("Newtonsoft.Json.Bson", "1.0.2", DependencyType.PackageReference)
            };
            var update = new[]
            {
                new Dependency("Newtonsoft.Json", "13.0.1", DependencyType.Unknown)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(2, resolvedDependencies.Length);
            Assert.Equal("Newtonsoft.Json.Bson", resolvedDependencies[0].Name);
            Assert.Equal("1.0.2", resolvedDependencies[0].Version);
            Assert.Equal("Newtonsoft.Json", resolvedDependencies[1].Name);
            Assert.Equal("13.0.1", resolvedDependencies[1].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 4, updating a package not in the existing list
    // Microsoft.CodeAnalysis.Compilers, Microsoft.CodeAnalysis.CSharp, and Microsoft.CodeAnalysis.VisualBasic are all 4.9.2
    // Csharp, Visual Basic, and Compilers all require Microsoft.CodeAnalysis.Common to be 4.9.2, but it's not in the existing list
    // If Microsoft.CodeAnalysis.Common is updated to  4.10.0, everything else updates and Microsoft.CoseAnalysis.Common is not kept in the exisiting list
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewTransitiveDependencyNotIncluded()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewTransitiveDependencyNotIncluded)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Compilers", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.VisualBasic", "4.9.2", DependencyType.PackageReference)
            };
            var update = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Common", "4.10.0", DependencyType.PackageReference)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(3, resolvedDependencies.Length);
            Assert.Equal("Microsoft.CodeAnalysis.Compilers", resolvedDependencies[0].Name);
            Assert.Equal("4.10.0", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp", resolvedDependencies[1].Name);
            Assert.Equal("4.10.0", resolvedDependencies[1].Version);
            Assert.Equal("Microsoft.CodeAnalysis.VisualBasic", resolvedDependencies[2].Name);
            Assert.Equal("4.10.0", resolvedDependencies[2].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 5, same as scenario 4, but the package is in the existing list
    // Single transitive dependency (Microsoft.CodeAnalysis.Common) gets updated, which then updates the top level package
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewSingleTransitiveDependency()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewSingleTransitiveDependency)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Compilers", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.Common", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.VisualBasic", "4.9.2", DependencyType.PackageReference)
            };
            var update = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Common", "4.10.0", DependencyType.PackageReference)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(4, resolvedDependencies.Length);
            Assert.Equal("Microsoft.CodeAnalysis.Compilers", resolvedDependencies[0].Name);
            Assert.Equal("4.10.0", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.Common", resolvedDependencies[1].Name);
            Assert.Equal("4.10.0", resolvedDependencies[1].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp", resolvedDependencies[2].Name);
            Assert.Equal("4.10.0", resolvedDependencies[2].Version);
            Assert.Equal("Microsoft.CodeAnalysis.VisualBasic", resolvedDependencies[3].Name);
            Assert.Equal("4.10.0", resolvedDependencies[3].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 6
    // A combination of the past two scenariors, updating 2 packages not in the exisiting list
    // Keeping a dependency that was not included in the original list (Newtonsoft.Json)
    // Not keeping a dependency that was not included in the original list (Microsoft.CodeAnalysis.Common)
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewSelectiveAdditionPackages()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewSelectiveAdditionPackages)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Compilers", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.VisualBasic", "4.9.2", DependencyType.PackageReference),
                new Dependency("Newtonsoft.Json.Bson", "1.0.2", DependencyType.PackageReference)
            };
            var update = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Common", "4.10.0", DependencyType.PackageReference),
                new Dependency("Newtonsoft.Json", "13.0.1", DependencyType.Unknown)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(5, resolvedDependencies.Length);
            Assert.Equal("Microsoft.CodeAnalysis.Compilers", resolvedDependencies[0].Name);
            Assert.Equal("4.10.0", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp", resolvedDependencies[1].Name);
            Assert.Equal("4.10.0", resolvedDependencies[1].Version);
            Assert.Equal("Microsoft.CodeAnalysis.VisualBasic", resolvedDependencies[2].Name);
            Assert.Equal("4.10.0", resolvedDependencies[2].Version);
            Assert.Equal("Newtonsoft.Json.Bson", resolvedDependencies[3].Name);
            Assert.Equal("1.0.2", resolvedDependencies[3].Version);
            Assert.Equal("Newtonsoft.Json", resolvedDependencies[4].Name);
            Assert.Equal("13.0.1", resolvedDependencies[4].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 7
    //  Two top level packages that share a dependency, updating ONE of the top level packages, which updates the children and the children't other "parents"
    //  Buildalyzer 7.0.1 requires Microsoft.CodeAnalysis.CSharp to be >= 4.0.0 and Microsoft.CodeAnalysis.Common to be 4.10.0 (@ 6.0.4, Microsoft.CodeAnalysis.Common isnt a dependency of buildalyzer)
    //  Microsoft.CodeAnalysis.CSharp.Scripting 4.4.0 requires Microsoft.CodeAnalysis.CSharp 4.4.0 and Microsoft.CodeAnalysis.Common to be 4.4.0 (Specific version) in oprder to update Microsoft.CodeAnalysis.Common to Buildalyzer to 7.0.1
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewSharingDependency()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewSharingDependency)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("Buildalyzer", "6.0.4", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp.Scripting", "3.10.0", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp", "3.10.0", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.Common", "3.10.0", DependencyType.PackageReference),
            };
            var update = new[]
            {
                new Dependency("Buildalyzer", "7.0.1", DependencyType.PackageReference),
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(4, resolvedDependencies.Length);
            Assert.Equal("Buildalyzer", resolvedDependencies[0].Name);
            Assert.Equal("7.0.1", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp.Scripting", resolvedDependencies[1].Name);
            Assert.Equal("4.0.0", resolvedDependencies[1].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp", resolvedDependencies[2].Name);
            Assert.Equal("4.0.0", resolvedDependencies[2].Version);
            Assert.Equal("Microsoft.CodeAnalysis.Common", resolvedDependencies[3].Name);
            Assert.Equal("4.0.0", resolvedDependencies[3].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 8
    // Update a dependency, which will then updates a transitive dependency of the top level package, and a parent. The dependency is not added to the exisiting list
    // Additionally, updating a top level package to update the dependency
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingEntireFamily()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewUpdatingEntireFamily)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("System.Collections.Immutable", "7.0.0", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp.Scripting", "4.9.2", DependencyType.PackageReference),
                new Dependency("System.Text.Json", "4.6.0", DependencyType.Unknown),
                new Dependency("Azure.Core", "1.21.0", DependencyType.PackageReference),

            };
            var update = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Common", "4.10.0", DependencyType.PackageReference),
                new Dependency("Azure.Core", "1.22.0", DependencyType.PackageReference)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(4, resolvedDependencies.Length);
            Assert.Equal("System.Collections.Immutable", resolvedDependencies[0].Name);
            Assert.Equal("8.0.0", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp.Scripting", resolvedDependencies[1].Name);
            Assert.Equal("4.10.0", resolvedDependencies[1].Version);
            Assert.Equal("System.Text.Json", resolvedDependencies[2].Name);
            Assert.Equal("4.7.2", resolvedDependencies[2].Version);
            Assert.Equal("Azure.Core", resolvedDependencies[3].Name);
            Assert.Equal("1.22.0", resolvedDependencies[3].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 9
    // Two separate root packages that need both need their separate dependencies updated
    // One dependency is not specified to be updated, only the root package is
    // Two separate resolvings. If we update Azure.Core (root) to the next update, System.Text.Json needs to be greater than or equal to 4.7.2. System.Text.Json is not in the existing packages.
    // System.Collections.Immutable needs to update to 8.0.0 or > and Microsoft.CodeAnalysis.Common NEEDS to be 4.10.0 (specific).
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUpdatingTopLevelAndDependency()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewUpdatingTopLevelAndDependency)}_");

        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("System.Collections.Immutable", "7.0.0", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.CSharp.Scripting", "4.9.2", DependencyType.PackageReference),
                new Dependency("Microsoft.CodeAnalysis.Common", "4.9.2", DependencyType.PackageReference),
                new Dependency("System.Text.Json", "4.6.0", DependencyType.Unknown),
                new Dependency("Azure.Core", "1.21.0", DependencyType.PackageReference),

            };
            var update = new[]
            {
                new Dependency("Microsoft.CodeAnalysis.Common", "4.10.0", DependencyType.PackageReference),
                new Dependency("Azure.Core", "1.22.0", DependencyType.PackageReference)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(5, resolvedDependencies.Length);
            Assert.Equal("System.Collections.Immutable", resolvedDependencies[0].Name);
            Assert.Equal("8.0.0", resolvedDependencies[0].Version);
            Assert.Equal("Microsoft.CodeAnalysis.CSharp.Scripting", resolvedDependencies[1].Name);
            Assert.Equal("4.10.0", resolvedDependencies[1].Version);
            Assert.Equal("Microsoft.CodeAnalysis.Common", resolvedDependencies[2].Name);
            Assert.Equal("4.10.0", resolvedDependencies[2].Version);
            Assert.Equal("System.Text.Json", resolvedDependencies[3].Name);
            Assert.Equal("4.7.2", resolvedDependencies[3].Version);
            Assert.Equal("Azure.Core", resolvedDependencies[4].Name);
            Assert.Equal("1.22.0", resolvedDependencies[4].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }

    // Scenario 10
    // Unsolveable
    // To update AutoMapper.Collection to 10.0.0, AutoMapper needs to update to 13.0.0 but there is no higher version of AutoMapper.Extensions.Microsoft.DependencyInjection
    [Fact]
    public async Task DependencyConflictsCanBeResolvedNewUnsolveable()
    {
        var repoRoot = Directory.CreateTempSubdirectory($"test_{nameof(DependencyConflictsCanBeResolvedNewUnsolveable)}_");
        
        try
        {
            var projectPath = Path.Join(repoRoot.FullName, "project.csproj");

            var dependencies = new[]
            {
                new Dependency("AutoMapper.Extensions.Microsoft.DependencyInjection", "12.0.1", DependencyType.PackageReference),
                new Dependency("AutoMapper", "12.0.1", DependencyType.PackageReference),
                new Dependency("AutoMapper.Collection", "9.0.0", DependencyType.PackageReference)
            };
            var update = new[]
            {
                new Dependency("AutoMapper.Collection", "10.0.0", DependencyType.PackageReference)
            };

            var resolvedDependencies = await MSBuildHelper.ResolveDependencyConflictsNew(repoRoot.FullName, projectPath, "net8.0", dependencies, update, new Logger(true));
            Assert.NotNull(resolvedDependencies);
            Assert.Equal(3, resolvedDependencies.Length);
            Assert.Equal("AutoMapper.Extensions.Microsoft.DependencyInjection", resolvedDependencies[0].Name);
            Assert.Equal("12.0.1", resolvedDependencies[0].Version);
            Assert.Equal("AutoMapper", resolvedDependencies[1].Name);
            Assert.Equal("12.0.1", resolvedDependencies[1].Version);
            Assert.Equal("AutoMapper.Collection", resolvedDependencies[2].Name);
            Assert.Equal("9.0.0", resolvedDependencies[2].Version);
        }
        finally
        {
            repoRoot.Delete(recursive: true);
        }
    }


    public static IEnumerable<object[]> GetTopLevelPackageDependencyInfosTestData()
    {
        // simple case
        yield return
        [
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "12.0.1", "12.0.1", null, null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        ];

        // version is a child-node of the package reference
        yield return
        [
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Package">
                            <Version>12.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "12.0.1", "12.0.1", null, null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        ];

        // version is in property in same file
        yield return
        [
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomePackageVersion>12.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(SomePackageVersion)", "12.0.1", "SomePackageVersion", null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        ];

        // version is a property not triggered by a condition
        yield return
        [
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                        <SomePackageVersion>12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(PropertyThatDoesNotExist) == 'true'">13.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(SomePackageVersion)", "12.0.1", "SomePackageVersion", null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        ];

        // version is a property not triggered by a quoted condition
        yield return new object[]
        {
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                        <SomePackageVersion>12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="'$(PropertyThatDoesNotExist)' == 'true'">13.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(SomePackageVersion)", "12.0.1", "SomePackageVersion", null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        };

        // version is a property with a condition checking for an empty string
        yield return
        [
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                        <SomePackageVersion Condition="$(SomePackageVersion) == ''">12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(PropertyThatDoesNotExist) == 'true'">13.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(SomePackageVersion)", "12.0.1", "SomePackageVersion", null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        ];

        // version is a property with a quoted condition checking for an empty string
        yield return new object[]
        {
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                        <SomePackageVersion Condition="'$(SomePackageVersion)' == ''">12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="'$(PropertyThatDoesNotExist)' == 'true'">13.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Some.Package",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(SomePackageVersion)", "12.0.1", "SomePackageVersion", null))
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0")
            }
        };

        // version is set in one file, used in another
        yield return
        [
            // build file contents
            new[]
            {
                ("Packages.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Update="Package.A" Version="1.6.0" />
                            <PackageReference Update="Package.B" Version="5.1.4" />
                          </ItemGroup>
                        </Project>
                    """),
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" Version="1.6.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Package.A",
                    "1.6.0",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "1.6.0", "1.6.0", null, null)),
                new(
                    "Package.B",
                    "5.1.4",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "5.1.4", "5.1.4", null, null),
                    IsUpdate: true),
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Package.A", "1.6.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.A", "1.6.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "5.1.4", "net8.0"),
            }
        ];

        // version is set in one file, used in another
        yield return
        [
            // build file contents
            new[]
            {
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Update="Package.A" Version="1.6.0" />
                            <PackageReference Update="Package.B" Version="5.1.4" />
                          </ItemGroup>
                        </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Package.A",
                    "1.6.0",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "1.6.0", "1.6.0", null, null)),
                new(
                    "Package.B",
                    "5.1.4",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "5.1.4", "5.1.4", null, null),
                    IsUpdate: true),
            },
            new MockNuGetPackage[]
            {
                MockNuGetPackage.CreateSimplePackage("Package.A", "1.6.0", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Package.B", "5.1.4", "net8.0"),
            }
        ];
    }

    public static IEnumerable<object[]> SolutionProjectPathTestData()
    {
        yield return
        [
            """
            Microsoft Visual Studio Solution File, Format Version 12.00
            # Visual Studio 14
            VisualStudioVersion = 14.0.22705.0
            MinimumVisualStudioVersion = 10.0.40219.1
            Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Some.Project", "src\Some.Project\SomeProject.csproj", "{782E0C0A-10D3-444D-9640-263D03D2B20C}"
            EndProject
            Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Some.Project.Test", "src\Some.Project.Test\Some.Project.Test.csproj", "{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}"
            EndProject
            Global
            	GlobalSection(SolutionConfigurationPlatforms) = preSolution
            		Debug|Any CPU = Debug|Any CPU
            		Release|Any CPU = Release|Any CPU
            	EndGlobalSection
            	GlobalSection(ProjectConfigurationPlatforms) = postSolution
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Debug|Any CPU.Build.0 = Debug|Any CPU
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Release|Any CPU.ActiveCfg = Release|Any CPU
            		{782E0C0A-10D3-444D-9640-263D03D2B20C}.Release|Any CPU.Build.0 = Release|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Debug|Any CPU.ActiveCfg = Debug|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Debug|Any CPU.Build.0 = Debug|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Release|Any CPU.ActiveCfg = Release|Any CPU
            		{5C15FD5B-1975-4CEA-8F1B-C0C9174C60A9}.Release|Any CPU.Build.0 = Release|Any CPU
            	EndGlobalSection
            	GlobalSection(SolutionProperties) = preSolution
            		HideSolutionNode = FALSE
            	EndGlobalSection
            EndGlobal
            """,
            new[]
            {
                "src/Some.Project/SomeProject.csproj",
                "src/Some.Project.Test/Some.Project.Test.csproj",
            }
        ];
    }
}
