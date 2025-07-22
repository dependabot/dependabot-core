using System.Text.Json;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

using TestFile = (string Path, string Content);

public class MSBuildHelperTests : TestBase
{
    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task AllPackageDependenciesCanBeTraversed(bool useExistingSdks)
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
            new("Package.A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["netstandard2.0"], IsDirect: true),
            new("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Package.C", "3.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Package.D", "4.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
        ];
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "netstandard2.0",
            [new Dependency("Package.A", "1.0.0", DependencyType.Unknown)],
            new ExperimentsManager() { InstallDotnetSdks = useExistingSdks },
            new TestLogger()
        );
        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task AllPackageDependencies_DoNotTruncateLongDependencyLists(bool useExistingSdks)
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
            new("Package.1A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
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
            new("Package.1R", "18.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
            new("Package.1S", "19.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1T", "20.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1U", "21.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1V", "22.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1W", "23.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1X", "24.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1Y", "25.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.1Z", "26.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
            new("Package.2A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
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
            new("Package.2R", "18.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect : true),
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
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "net8.0",
            packages,
            new ExperimentsManager() { InstallDotnetSdks = useExistingSdks },
            new TestLogger()
        );
        for (int i = 0; i < actualDependencies.Length; i++)
        {
            var ad = actualDependencies[i];
            var ed = expectedDependencies[i];
            Assert.Equal(ed, ad);
        }

        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task AllPackageDependencies_DoNotIncludeUpdateOnlyPackages(bool useExistingSdks)
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
            new("Package.A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
            new("Package.B", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect: true),
        ];
        var packages = new[]
        {
            new Dependency("Package.A", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new Dependency("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
            new Dependency("Package.C", "3.0.0", DependencyType.Unknown, IsUpdate: true)
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "net8.0",
            packages,
            new ExperimentsManager() { InstallDotnetSdks = useExistingSdks },
            new TestLogger()
        );
        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task GetAllPackageDependencies_NugetConfigInvalid_DoesNotThrow(bool useExistingSdks)
    {
        using var temp = new TemporaryDirectory();

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
            """, TestContext.Current.CancellationToken);

        // Asserting it didn't throw
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "net8.0",
            [new Dependency("Some.Package", "4.5.11", DependencyType.Unknown)],
            new ExperimentsManager() { InstallDotnetSdks = useExistingSdks },
            new TestLogger()
        );
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task LocalPackageSourcesAreHonored(bool useExistingSdks)
    {
        using var temp = new TemporaryDirectory();

        // create two local package sources with different packages available in each
        string localSource1 = Path.Combine(temp.DirectoryPath, "local", "source1");
        Directory.CreateDirectory(localSource1);
        string localSource2 = Path.Combine(temp.DirectoryPath, "local", "source2");
        Directory.CreateDirectory(localSource2);

        // `Package.A` will only live in `local\source1` and uses Windows-style directory separators and will have
        // a dependency on `Package.B` which is only available in `local/source2` and uses Unix-style directory
        // separators.
        MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net8.0", [(null, [("Package.B", "2.0.0")])]).WriteToDirectory(localSource1);
        MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net8.0").WriteToDirectory(localSource2);
        await File.WriteAllTextAsync(Path.Join(temp.DirectoryPath, "NuGet.Config"), """
            <configuration>
                <packageSources>
                <add key="localSource1" value="local\source1" />
                <add key="localSource2" value="local/source2" />
                </packageSources>
            </configuration>
            """, TestContext.Current.CancellationToken);

        Dependency[] expectedDependencies =
        [
            new("Package.A", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net8.0"], IsDirect : true),
            new("Package.B", "2.0.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"], IsTransitive: true),
        ];

        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "net8.0",
            [new Dependency("Package.A", "1.0.0", DependencyType.Unknown)],
            new ExperimentsManager() { InstallDotnetSdks = useExistingSdks },
            new TestLogger()
        );

        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Theory]
    [MemberData(nameof(GetTargetFrameworkValuesFromProjectData))]
    public async Task GetTargetFrameworkValuesFromProject(string projectContents, string[] expectedTfms)
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
        [
            ("Directory.Build.props", "<Project />"),
            ("Directory.Build.targets", "<Project />"),
            ("project.csproj", projectContents)
        ]);
        var projectPath = Path.Combine(tempDir.DirectoryPath, "project.csproj");
        var experimentsManager = new ExperimentsManager();
        var logger = new TestLogger();
        var actualTfms = await MSBuildHelper.GetTargetFrameworkValuesFromProject(tempDir.DirectoryPath, projectPath, experimentsManager, logger);
        AssertEx.Equal(expectedTfms, actualTfms);
    }

    public static IEnumerable<object[]> GetTargetFrameworkValuesFromProjectData()
    {
        // SDK-style projects
        yield return
        [
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net8.0</TargetFramework>
              </PropertyGroup>
            </Project>
            """,
            new[] { "net8.0" }
        ];

        yield return
        [
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFrameworks> ; net8.0 ; </TargetFrameworks>
              </PropertyGroup>
            </Project>
            """,
            new[] { "net8.0" }
        ];

        yield return
        [
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFrameworks>net8.0;net9.0</TargetFrameworks>
              </PropertyGroup>
            </Project>
            """,
            new[] { "net8.0", "net9.0" }
        ];

        yield return
        [
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net8.0-windows7.0</TargetFramework>
              </PropertyGroup>
            </Project>
            """,
            new[] { "net8.0-windows7.0" }
        ];

        yield return
        [
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net9.0-windows</TargetFramework>
              </PropertyGroup>
            </Project>
            """,
            new[] { "net9.0-windows" }
        ];

        // legacy projects
        yield return
        [
            """
            <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
              <PropertyGroup>
                <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
              </PropertyGroup>
              <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
            </Project>
            """,
            new[] { "net45" }
        ];
    }

    [Theory]
    [MemberData(nameof(GenerateErrorFromToolOutputTestData))]
    public async Task GenerateErrorFromToolOutput(string output, JobErrorBase? expectedError)
    {
        Exception? exception = null;
        try
        {
            MSBuildHelper.ThrowOnError(output);
        }
        catch (Exception ex)
        {
            exception = ex;
        }

        if (expectedError is null)
        {
            Assert.Null(exception);
        }
        else
        {
            Assert.NotNull(exception);
            using var tempDir = await TemporaryDirectory.CreateWithContentsAsync([("NuGet.Config", """
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="test-feed" value="http://localhost/test-feed" />
                  </packageSources>
                </configuration>
                """)]);
            var actualError = JobErrorBase.ErrorFromException(exception, "TEST-JOB-ID", tempDir.DirectoryPath);
            if (actualError is DependencyFileNotFound notFound)
            {
                // normalize default message for the test
                actualError = new DependencyFileNotFound(notFound.Details["file-path"].ToString()!, "test message");
            }

            var actualErrorJson = JsonSerializer.Serialize(actualError, RunWorker.SerializerOptions);
            var expectedErrorJson = JsonSerializer.Serialize(expectedError, RunWorker.SerializerOptions);
            Assert.Equal(expectedErrorJson, actualErrorJson);
        }
    }

    public static IEnumerable<object?[]> GenerateErrorFromToolOutputTestData()
    {
        yield return
        [
            // output
            "Everything was good.",
            // expectedError
            null,
        ];

        yield return
        [
            // output
            "Response status code does not indicate success: 401",
            // expectedError
            new PrivateSourceAuthenticationFailure(["http://localhost/test-feed"]),
        ];

        yield return
        [
            // output
            "Response status code does not indicate success: 403",
            // expectedError
            new PrivateSourceAuthenticationFailure(["http://localhost/test-feed"]),
        ];

        yield return
        [
            // output
            "Response status code does not indicate success: 500 (Internal Server Error).",
            // expectedError
            new PrivateSourceBadResponse(["http://localhost/test-feed"]),
        ];

        yield return
        [
            // output
            "The response ended prematurely. (ResponseEnded)",
            // expectedError
            new PrivateSourceBadResponse(["http://localhost/test-feed"]),
        ];

        yield return
        [
            // output
            "The file is not a valid nupkg.",
            // expectedError
            new PrivateSourceBadResponse(["http://localhost/test-feed"]),
        ];

        yield return
        [
            // output
            "The content at 'http://localhost/test-feed/Packages(Id='Some.Package',Version='1.2.3')' is not valid XML.",
            // expectedError
            new PrivateSourceBadResponse(["http://localhost/test-feed"]),
        ];

        yield return
        [
            // output
            "  The HTTP request to 'GET some-source' has timed out after 100000ms.",
            // expectedError
            new PrivateSourceTimedOut("some-source"),
        ];

        yield return
        [
            // output
            "The imported file \"some.file\" does not exist",
            // expectedError
            new DependencyFileNotFound("some.file", "test message"),
        ];

        yield return
        [
            // output
            "Package 'Some.Package' is not found on source 'some-source'.",
            // expectedError
            new DependencyNotFound("Some.Package"),
        ];

        yield return
        [
            // output
            "error NU1101: Unable to find package Some.Package. No packages exist with this id in source(s): some-source",
            // expectedError
            new DependencyNotFound("Some.Package"),
        ];

        yield return
        [
            // output
            "Unable to find package Some.Package with version (= 1.2.3)",
            // expectedError
            new DependencyNotFound("Some.Package/= 1.2.3"),
        ];

        yield return
        [
            // output
            """error : Could not resolve SDK "missing-sdk".""",
            // expectedError
            new DependencyNotFound("missing-sdk"),
        ];

        yield return
        [
            // output
            "Unable to find package 'Some.Package'. Existing packages must be restored before performing an install or update",
            // expectedError
            new DependencyNotFound("Some.Package"),
        ];

        yield return
        [
            // output
            "Unable to resolve dependency 'Some.Package'. Source(s) used: 'nuget.org'.",
            // expectedError
            new DependencyNotFound("Some.Package"),
        ];

        yield return
        [
            // output
            "Unable to resolve dependencies. 'Some.Package 1.2.3' is not compatible with",
            // expectedError
            new UpdateNotPossible(["Some.Package.1.2.3"]),
        ];

        yield return
        [
            // output
            "Could not install package 'Some.Package 1.2.3'. You are trying to install this package into a project that targets 'SomeFramework'",
            // expectedError
            new UpdateNotPossible(["Some.Package.1.2.3"]),
        ];

        yield return
        [
            // output
            "Unable to find a version of 'Some.Package' that is compatible with 'Some.Other.Package 4.5.6 constraint: Some.Package (>= 1.2.3)'",
            // expectedError
            new UpdateNotPossible(["Some.Package.1.2.3"]),
        ];

        yield return
        [
            // output
            "the following error(s) may be blocking the current package operation: 'Some.Package 1.2.3 constraint: Some.Other.Package (>= 4.5.6)'",
            // expectedError
            new UpdateNotPossible(["Some.Package.1.2.3"]),
        ];

        yield return
        [
            // output
            "Unable to resolve 'Some.Package'. An additional constraint '(= 1.2.3)' defined in packages.config prevents this operation.",
            // expectedError
            new UpdateNotPossible(["Some.Package.= 1.2.3"]),
        ];

        yield return
        [
            // output
            "Failed to fetch results from V2 feed at 'http://nuget.example.com/FindPackagesById()?id='Some.Package'&semVerLevel=2.0.0' with following message : Response status code does not indicate success: 404.",
            // expectedError
            new DependencyNotFound("Some.Package"),
        ];

        yield return
        [
            // output
            "This part is not reported.\nAn error occurred while reading file '/path/to/packages.config': Some error message.\nThis part is not reported.",
            // expectedError
            new DependencyFileNotParseable("/path/to/packages.config", "Some error message."),
        ];

        yield return
        [
            // output
            """
            NuGet.Config is not valid XML. Path: '/path/to/NuGet.Config'.
              Some error message.
            """,
            // expectedError
            new DependencyFileNotParseable("/path/to/NuGet.Config", "Some error message."),
        ];
    }
}
