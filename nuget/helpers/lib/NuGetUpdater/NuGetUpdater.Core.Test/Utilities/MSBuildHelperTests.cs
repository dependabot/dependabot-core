using System.Collections.Immutable;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

using TestFile = (string Path, string Content);

public class MSBuildHelperTests
{
    public MSBuildHelperTests()
    {
        MSBuildHelper.RegisterMSBuild();
    }

    [Fact]
    public void GetRootedValue_FindsValue()
    {
        // Arrange
        var projectContents = """
            <Project>
                <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="$(PackageVersion1)" />
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
                    <TargetFramework>netstandard2.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="1.1.1" />
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
                    <TargetFramework>netstandard2.0</TargetFramework>
                </PropertyGroup>
                <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="$(PackageVersion1)" />
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
    public void TfmsCanBeDeterminedFromProjectContents(string projectContents, string? expectedTfm1, string? expectedTfm2)
    {
        var projectPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(projectPath, projectContents);
            var expectedTfms = new[] { expectedTfm1, expectedTfm2 }.Where(tfm => tfm is not null).ToArray();
            var buildFile = ProjectBuildFile.Open(Path.GetDirectoryName(projectPath)!, projectPath);
            var actualTfms = MSBuildHelper.GetTargetFrameworkMonikers(ImmutableArray.Create(buildFile));
            AssertEx.Equal(expectedTfms, actualTfms);
        }
        finally
        {
            File.Delete(projectPath);
        }
    }

    [Theory]
    [MemberData(nameof(GetTopLevelPackageDependencyInfosTestData))]
    public async Task TopLevelPackageDependenciesCanBeDetermined(TestFile[] buildFileContents, Dependency[] expectedTopLevelDependencies)
    {
        using var testDirectory = new TemporaryDirectory();
        var buildFiles = new List<ProjectBuildFile>();
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
        var expectedDependencies = new Dependency[]
        {
            new("Microsoft.Bcl.AsyncInterfaces", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DependencyInjection", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DependencyInjection.Abstractions", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Http", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.Extensions.Logging", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Logging.Abstractions", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Options", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Primitives", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Buffers", "4.5.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ComponentModel.Annotations", "5.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Diagnostics.DiagnosticSource", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Memory", "4.5.5", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Numerics.Vectors", "4.4.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.CompilerServices.Unsafe", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Threading.Tasks.Extensions", "4.5.4", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("NETStandard.Library", "2.0.3", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
            temp.DirectoryPath,
            temp.DirectoryPath,
            "netstandard2.0",
            [new Dependency("Microsoft.Extensions.Http", "7.0.0", DependencyType.Unknown)]);
        AssertEx.Equal(expectedDependencies, actualDependencies);
    }

    [Fact]
    public async Task AllPackageDependencies_DoNotTruncateLongDependencyLists()
    {
        using var temp = new TemporaryDirectory();
        var expectedDependencies = new Dependency[]
        {
            new("Castle.Core", "4.4.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.ApplicationInsights", "2.10.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.ApplicationInsights.Agent.Intercept", "2.4.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.ApplicationInsights.DependencyCollector", "2.10.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.ApplicationInsights.PerfCounterCollector", "2.10.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.ApplicationInsights.WindowsServer", "2.10.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.ApplicationInsights.WindowsServer.TelemetryChannel", "2.10.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.AspNet.TelemetryCorrelation", "1.0.5", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Bcl.AsyncInterfaces", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Caching.Abstractions", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Caching.Memory", "1.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DependencyInjection", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DependencyInjection.Abstractions", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DiagnosticAdapter", "1.1.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Http", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.Extensions.Logging", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Logging.Abstractions", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Options", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.PlatformAbstractions", "1.1.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Primitives", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Moq", "4.16.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("MSTest.TestFramework", "2.1.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Newtonsoft.Json", "12.0.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("System", "4.1.311.2", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("System.Buffers", "4.5.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Collections.Concurrent", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Collections.Immutable", "1.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Collections.NonGeneric", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Collections.Specialized", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ComponentModel", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ComponentModel.Annotations", "5.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ComponentModel.Primitives", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ComponentModel.TypeConverter", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Core", "3.5.21022.801", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("System.Data.Common", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Diagnostics.DiagnosticSource", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Diagnostics.PerformanceCounter", "4.5.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Diagnostics.StackTrace", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Dynamic.Runtime", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.IO.FileSystem.Primitives", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Linq", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Linq.Expressions", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Memory", "4.5.5", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Net.WebHeaderCollection", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Numerics.Vectors", "4.4.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ObjectModel", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Private.DataContractSerialization", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Reflection.Emit", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Reflection.Emit.ILGeneration", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Reflection.Emit.Lightweight", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Reflection.Metadata", "1.4.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Reflection.TypeExtensions", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.CompilerServices.Unsafe", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.InteropServices.RuntimeInformation", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.Numerics", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.Serialization.Json", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.Serialization.Primitives", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Security.Claims", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Security.Cryptography.OpenSsl", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Security.Cryptography.Primitives", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Security.Principal", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Text.RegularExpressions", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Threading", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Threading.Tasks.Extensions", "4.5.4", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Threading.Thread", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Threading.ThreadPool", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Xml.ReaderWriter", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Xml.XDocument", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Xml.XmlDocument", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Xml.XmlSerializer", "4.3.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.ApplicationInsights.Web", "2.10.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("MSTest.TestAdapter", "2.1.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("NETStandard.Library", "2.0.3", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
        };
        var packages = new[]
        {
            new Dependency("System", "4.1.311.2", DependencyType.Unknown),
            new Dependency("System.Core", "3.5.21022.801", DependencyType.Unknown),
            new Dependency("Moq", "4.16.1", DependencyType.Unknown),
            new Dependency("Castle.Core", "4.4.1", DependencyType.Unknown),
            new Dependency("MSTest.TestAdapter", "2.1.0", DependencyType.Unknown),
            new Dependency("MSTest.TestFramework", "2.1.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights", "2.10.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights.Agent.Intercept", "2.4.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights.DependencyCollector", "2.10.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights.PerfCounterCollector", "2.10.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights.Web", "2.10.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights.WindowsServer.TelemetryChannel", "2.10.0", DependencyType.Unknown),
            new Dependency("Microsoft.ApplicationInsights.WindowsServer", "2.10.0", DependencyType.Unknown),
            new Dependency("Microsoft.Extensions.Http", "7.0.0", DependencyType.Unknown),
            new Dependency("Newtonsoft.Json", "12.0.1", DependencyType.Unknown)
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, temp.DirectoryPath, "netstandard2.0", packages);
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
        var expectedDependencies = new Dependency[]
        {
            new("Microsoft.Bcl.AsyncInterfaces", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DependencyInjection", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.DependencyInjection.Abstractions", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Http", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
            new("Microsoft.Extensions.Logging", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Logging.Abstractions", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Options", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("Microsoft.Extensions.Primitives", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Buffers", "4.5.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.ComponentModel.Annotations", "5.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Diagnostics.DiagnosticSource", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Memory", "4.5.5", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Numerics.Vectors", "4.4.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Runtime.CompilerServices.Unsafe", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("System.Threading.Tasks.Extensions", "4.5.4", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            new("NETStandard.Library", "2.0.3", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
        };
        var packages = new[]
        {
            new Dependency("Microsoft.Extensions.Http", "7.0.0", DependencyType.Unknown),
            new Dependency("Newtonsoft.Json", "12.0.1", DependencyType.Unknown, IsUpdate: true)
        };
        var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(temp.DirectoryPath, temp.DirectoryPath, "netstandard2.0", packages);
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
                "netstandard2.0",
                [new Dependency("Newtonsoft.Json", "4.5.11", DependencyType.Unknown)]
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
    public async Task GetAllPackageDependencies_LocalNuGetRepos_AreCopiedToTempProject()
    {
        // If we end up using this EnvVar pattern again I think it'd be worth it to abstract it out into an IDisposable.
        var nugetPackagesDirectory = Environment.GetEnvironmentVariable("NUGET_PACKAGES");
        var nugetHttpCacheDirectory = Environment.GetEnvironmentVariable("NUGET_HTTP_CACHE_PATH");
        var logger = new Logger(verbose: true);
        try
        {
            // First create a fake local nuget repository
            using var restoreDir = new TemporaryDirectory();

            var restoreNuGetPackagesDirectory = Path.Combine(restoreDir.DirectoryPath, ".nuget", "packages");
            Environment.SetEnvironmentVariable("NUGET_PACKAGES", restoreNuGetPackagesDirectory);
            var restoreNuGetHttpCacheDirectory = Path.Combine(restoreDir.DirectoryPath, ".nuget", "v3-cache");
            Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", restoreNuGetHttpCacheDirectory);

            using var temp = new TemporaryDirectory();
            using (var restoreProjectTemp = new TemporaryDirectory())
            {
                // dotnet restore .csproj with things we want
                await MSBuildHelper.DependenciesAreCoherentAsync(restoreProjectTemp.DirectoryPath, restoreProjectTemp.DirectoryPath, "netstandard2.0",
                    [new Dependency("Newtonsoft.Json", "4.5.11", DependencyType.Unknown)], logger);
                Assert.True(Directory.Exists(restoreNuGetPackagesDirectory), "packages directory didn't exist");
                PathHelper.CopyDirectory(restoreNuGetPackagesDirectory, Path.Combine(temp.DirectoryPath, "local_repo"));
            }

            // It is important to have empty NuGet caches for this test, so override them with temp directories.
            var tempNuGetPackagesDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "packages");
            Environment.SetEnvironmentVariable("NUGET_PACKAGES", tempNuGetPackagesDirectory);
            var tempNuGetHttpCacheDirectory = Path.Combine(temp.DirectoryPath, ".nuget", "v3-cache");
            Environment.SetEnvironmentVariable("NUGET_HTTP_CACHE_PATH", tempNuGetHttpCacheDirectory);

            // Write the NuGet.config.
            await File.WriteAllTextAsync(
                Path.Combine(temp.DirectoryPath, "NuGet.Config"), """
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="local-repo" value="local_repo" />
                  </packageSources>
                </configuration>
                """);
            var expectedDependencies = new Dependency[]
            {
                new("Newtonsoft.Json", "4.5.11", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
                new("NETStandard.Library", "2.0.3", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            };
            var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                temp.DirectoryPath,
                temp.DirectoryPath,
                "netstandard2.0",
                [new Dependency("Newtonsoft.Json", "4.5.11", DependencyType.Unknown)]
            );
            Assert.False(Directory.Exists(tempNuGetHttpCacheDirectory), "The .nuget/.v3-cache directory was created, meaning http was used.");
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

            // First validate that we are unable to find dependencies for the package version without a NuGet.config.
            var dependenciesNoNuGetConfig = await MSBuildHelper.GetAllPackageDependenciesAsync(
                temp.DirectoryPath,
                temp.DirectoryPath,
                "netstandard2.0",
                [new Dependency("Microsoft.CodeAnalysis.Common", "4.8.0-3.23457.5", DependencyType.Unknown)]);
            Assert.Equal([], dependenciesNoNuGetConfig);

            // Write the NuGet.config and try again.
            await File.WriteAllTextAsync(
                Path.Combine(temp.DirectoryPath, "NuGet.Config"), """
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="dotnet-tools" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-tools/nuget/v3/index.json" />
                    <add key="dotnet-public" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-public/nuget/v3/index.json" />
                  </packageSources>
                </configuration>
                """);

            var expectedDependencies = new Dependency[]
            {
                new("Microsoft.CodeAnalysis.Common", "4.8.0-3.23457.5", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"]),
                new("System.Buffers", "4.5.1", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Collections.Immutable", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Memory", "4.5.5", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Numerics.Vectors", "4.4.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Reflection.Metadata", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Runtime.CompilerServices.Unsafe", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Text.Encoding.CodePages", "7.0.0", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("System.Threading.Tasks.Extensions", "4.5.4", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("Microsoft.CodeAnalysis.Analyzers", "3.3.4", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
                new("NETStandard.Library", "2.0.3", DependencyType.Unknown, TargetFrameworks: ["netstandard2.0"], IsTransitive: true),
            };
            var actualDependencies = await MSBuildHelper.GetAllPackageDependenciesAsync(
                temp.DirectoryPath,
                temp.DirectoryPath,
                "netstandard2.0",
                [new Dependency("Microsoft.CodeAnalysis.Common", "4.8.0-3.23457.5", DependencyType.Unknown)]
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
                        <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "12.0.1", "12.0.1", null, null))
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
                        <PackageReference Include="Newtonsoft.Json">
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
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "12.0.1", "12.0.1", null, null))
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
                        <NewtonsoftJsonVersion>12.0.1</NewtonsoftJsonVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(NewtonsoftJsonVersion)", "12.0.1", "NewtonsoftJsonVersion", null))
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
                        <NewtonsoftJsonVersion>12.0.1</NewtonsoftJsonVersion>
                        <NewtonsoftJsonVersion Condition="$(PropertyThatDoesNotExist) == 'true'">13.0.1</NewtonsoftJsonVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(NewtonsoftJsonVersion)", "12.0.1", "NewtonsoftJsonVersion", null))
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
                        <NewtonsoftJsonVersion>12.0.1</NewtonsoftJsonVersion>
                        <NewtonsoftJsonVersion Condition="'$(PropertyThatDoesNotExist)' == 'true'">13.0.1</NewtonsoftJsonVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(NewtonsoftJsonVersion)", "12.0.1", "NewtonsoftJsonVersion", null))
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
                        <NewtonsoftJsonVersion Condition="$(NewtonsoftJsonVersion) == ''">12.0.1</NewtonsoftJsonVersion>
                        <NewtonsoftJsonVersion Condition="$(PropertyThatDoesNotExist) == 'true'">13.0.1</NewtonsoftJsonVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(NewtonsoftJsonVersion)", "12.0.1", "NewtonsoftJsonVersion", null))
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
                        <NewtonsoftJsonVersion Condition="'$(NewtonsoftJsonVersion)' == ''">12.0.1</NewtonsoftJsonVersion>
                        <NewtonsoftJsonVersion Condition="'$(PropertyThatDoesNotExist)' == 'true'">13.0.1</NewtonsoftJsonVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Newtonsoft.Json",
                    "12.0.1",
                    DependencyType.PackageReference,
                    new(EvaluationResultType.Success, "$(NewtonsoftJsonVersion)", "12.0.1", "NewtonsoftJsonVersion", null))
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
                            <PackageReference Update="Azure.Identity" Version="1.6.0" />
                            <PackageReference Update="Microsoft.Data.SqlClient" Version="5.1.4" />
                          </ItemGroup>
                        </Project>
                    """),
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Azure.Identity" Version="1.6.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Azure.Identity",
                    "1.6.0",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "1.6.0", "1.6.0", null, null)),
                new(
                    "Microsoft.Data.SqlClient",
                    "5.1.4",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "5.1.4", "5.1.4", null, null),
                    IsUpdate: true),
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
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Azure.Identity" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Update="Azure.Identity" Version="1.6.0" />
                            <PackageReference Update="Microsoft.Data.SqlClient" Version="5.1.4" />
                          </ItemGroup>
                        </Project>
                    """)
            },
            // expected dependencies
            new Dependency[]
            {
                new(
                    "Azure.Identity",
                    "1.6.0",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "1.6.0", "1.6.0", null, null)),
                new(
                    "Microsoft.Data.SqlClient",
                    "5.1.4",
                    DependencyType.PackageReference,
                    EvaluationResult: new(EvaluationResultType.Success, "5.1.4", "5.1.4", null, null),
                    IsUpdate: true),
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
