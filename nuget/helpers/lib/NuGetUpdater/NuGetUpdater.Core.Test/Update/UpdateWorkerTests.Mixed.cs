using System.Text.Json;

using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class Mixed : UpdateWorkerTestBase
    {
        [Fact]
        public async Task ResultFileHasCorrectShapeForAuthenticationFailure()
        {
            using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync([]);
            var result = new UpdateOperationResult()
            {
                ErrorType = ErrorType.AuthenticationFailure,
                ErrorDetails = "<some package feed>",
            };
            var resultFilePath = Path.Combine(temporaryDirectory.DirectoryPath, "update-result.json");
            await UpdaterWorker.WriteResultFile(result, resultFilePath, new Logger(false));
            var resultContent = await File.ReadAllTextAsync(resultFilePath);

            // raw result file should look like this:
            // {
            //   ...
            //   "ErrorType": "AuthenticationFailure",
            //   "ErrorDetails": "<some package feed>",
            //   ...
            // }
            var jsonDocument = JsonDocument.Parse(resultContent);
            var errorType = jsonDocument.RootElement.GetProperty("ErrorType");
            var errorDetails = jsonDocument.RootElement.GetProperty("ErrorDetails");

            Assert.Equal("AuthenticationFailure", errorType.GetString());
            Assert.Equal("<some package feed>", errorDetails.GetString());
        }

        [Fact]
        public async Task ForPackagesProject_UpdatePackageReference_InBuildProps()
        {
            // update Some.Package from 7.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
                ],
                // existing
                projectContents: """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package">
                          <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                additionalFiles:
                [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="7.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.7.2</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package">
                          <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                        </packages>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]);
        }
    }
}
