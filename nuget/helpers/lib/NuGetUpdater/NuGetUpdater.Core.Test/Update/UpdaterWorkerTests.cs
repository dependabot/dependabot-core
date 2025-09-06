using NuGet.Versioning;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Test.DependencySolver;
using NuGetUpdater.Core.Test.Update.FileWriters;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class UpdaterWorkerTests : TestBase
{
    [Fact]
    public async Task AggregateUpdaterIsUsed()
    {
        // in this test, the first file editor can't make an appropriate edit, so the external service is invoked

        // arrange
        var initialProjectContents = """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net9.0</TargetFramework>
                <PackageMajorVersion>1</PackageMajorVersion>
                <PackageMinorVersion>0</PackageMinorVersion>
                <PackagePatchVersion>0</PackagePatchVersion>
                <PackageVersion>$(PackageMajorVersion).$(PackageMinorVersion).$(PackagePatchVersion)</PackageVersion>
              </PropertyGroup>
              <ItemGroup>
                <PackageReference Include="Some.Package" Version="$(PackageVersion)" />
              </ItemGroup>
            </Project>
            """;
        var finalProjectContents = """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>net9.0</TargetFramework>
                <PackageMajorVersion>1</PackageMajorVersion>
                <PackageMinorVersion>2</PackageMinorVersion>
                <PackagePatchVersion>3</PackagePatchVersion>
                <PackageVersion>$(PackageMajorVersion).$(PackageMinorVersion).$(PackagePatchVersion)</PackageVersion>
              </PropertyGroup>
              <ItemGroup>
                <PackageReference Include="Some.Package" Version="$(PackageVersion)" />
              </ItemGroup>
            </Project>
            """;
        var externalFileEditorWasInvoked = false;
        using var http = TestHttpServer.CreateTestStringServerWithBody((_url, _body) =>
        {
            // when explicitly asked, the external tool success in making an edit
            externalFileEditorWasInvoked = true;
            var response = new FileEditResponse()
            {
                Success = true,
                Files = [new() { Path = "/project.csproj", Content = finalProjectContents }],
            };
            return (200, ExternalFileWriter.SerializeResponse(response));
        });
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", initialProjectContents),
            ("Directory.Packages.props", """
                <Project>
                  <PropertyGroup>
                    <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                  </PropertyGroup>
                </Project>
                """)
        );

        // act
        var jobId = "TEST-JOB-ID";
        var logger = new TestLogger();
        var experimentsManager = new ExperimentsManager();
        var discoveryWorker = TestDiscoveryWorker.InOrder(
            // initial result
            new WorkspaceDiscoveryResult()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        ImportedFiles = [],
                        AdditionalFiles = [],
                        Dependencies = [new("Some.Package", "1.0.0", DependencyType.PackageReference)],
                        TargetFrameworks = ["net9.0"],
                    }
                ]
            },
            // successful check after external edit
            new WorkspaceDiscoveryResult()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "project.csproj",
                        ImportedFiles = [],
                        AdditionalFiles = [],
                        Dependencies = [new("Some.Package", "1.2.3", DependencyType.PackageReference)],
                        TargetFrameworks = ["net9.0"],
                    }
                ]
            }
        );
        var updater = new UpdaterWorker(
            jobId,
            discoveryWorker,
            _workspacePath => TestDependencySolver.Identity(),
            [TestFileWriterWrapper.FromConstantResult(false), new ExternalFileWriter(http.BaseUrl, logger)],
            (_repoRoot, _projectPath, _tfm, _topLevelDeps, _requestedUpdates, _resolvedDeps, _logger) =>
                Task.FromResult<IEnumerable<UpdateOperationBase>>([new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("1.2.3"), UpdatedFiles = ["/project.csproj"] }]),
            experimentsManager,
            logger);
        await updater.RunAsync(tempDir.DirectoryPath, "/project.csproj", "Some.Package", "1.0.0", "1.2.3", isTransitive: false);

        // assert
        Assert.True(externalFileEditorWasInvoked);
        var actualFileContents = await tempDir.ReadFileContentsAsync(["project.csproj"]);
        var actualProjectContents = actualFileContents[0].Contents;
        var expectedProjectContents = finalProjectContents;
        Assert.Equal(expectedProjectContents, actualProjectContents);
    }
}
