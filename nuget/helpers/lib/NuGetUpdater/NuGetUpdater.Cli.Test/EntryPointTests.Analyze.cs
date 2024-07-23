using System.Text;
using System.Xml.Linq;

using NuGetUpdater.Core;
using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Test;
using NuGetUpdater.Core.Test.Analyze;
using NuGetUpdater.Core.Test.Update;

using Xunit;

namespace NuGetUpdater.Cli.Test;

using TestFile = (string Path, string Content);

public partial class EntryPointTests
{
    public class Analyze : AnalyzeWorkerTestBase
    {
        [Fact]
        public async Task FindsUpdatedPackageAndReturnsTheCorrectData()
        {
            var repositoryXml = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some.package" />""");
            await RunAsync(path =>
                [
                    "analyze",
                    "--repo-root",
                    path,
                    "--discovery-file-path",
                    Path.Join(path, "discovery.json"),
                    "--dependency-file-path",
                    Path.Join(path, "Some.Package.json"),
                    "--analysis-folder-path",
                    Path.Join(path, AnalyzeWorker.AnalysisDirectoryName),
                    "--verbose",
                ],
                packages: [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", additionalMetadata: [repositoryXml]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net8.0", additionalMetadata: [repositoryXml]),
                ],
                dependencyName: "Some.Package",
                initialFiles:
                [
                    ("discovery.json", """
                        {
                          "Path": "",
                          "IsSuccess": true,
                          "Projects": [
                            {
                              "FilePath": "project.csproj",
                              "Dependencies": [
                                {
                                  "Name": "Microsoft.NET.Sdk",
                                  "Version": null,
                                  "Type": "MSBuildSdk",
                                  "EvaluationResult": null,
                                  "TargetFrameworks": null,
                                  "IsDevDependency": false,
                                  "IsDirect": false,
                                  "IsTransitive": false,
                                  "IsOverride": false,
                                  "IsUpdate": false
                                },
                                {
                                  "Name": "Some.Package",
                                  "Version": "1.0.0",
                                  "Type": "PackageReference",
                                  "EvaluationResult": {
                                    "ResultType": "Success",
                                    "OriginalValue": "1.0.0",
                                    "EvaluatedValue": "1.0.0",
                                    "RootPropertyName": null,
                                    "ErrorMessage": null
                                  },
                                  "TargetFrameworks": [
                                    "net8.0"
                                  ],
                                  "IsDevDependency": false,
                                  "IsDirect": true,
                                  "IsTransitive": false,
                                  "IsOverride": false,
                                  "IsUpdate": false
                                }
                              ],
                              "IsSuccess": true,
                              "Properties": [
                                {
                                  "Name": "TargetFramework",
                                  "Value": "net8.0",
                                  "SourceFilePath": "project.csproj"
                                }
                              ],
                              "TargetFrameworks": [
                                "net8.0"
                              ],
                              "ReferencedProjectPaths": []
                            }
                          ],
                          "DirectoryPackagesProps": null,
                          "GlobalJson": null,
                          "DotNetToolsJson": null
                        }
                        """),
                    ("Some.Package.json", """
                        {
                          "Name": "Some.Package",
                          "Version": "1.0.0",
                          "IsVulnerable": false,
                          "IgnoredVersions": [],
                          "Vulnerabilities": []
                        }
                        """),
                    ("project.csproj", """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                expectedResult: new()
                {
                    UpdatedVersion = "1.0.1",
                    CanUpdate = true,
                    VersionComesFromMultiDependencyProperty = false,
                    UpdatedDependencies =
                    [
                        new Dependency("Some.Package", "1.0.1", DependencyType.Unknown, TargetFrameworks: ["net8.0"], InfoUrl: "https://nuget.example.com/some.package")
                    ],
                }
            );
        }

        [Fact]
        public async Task DotNetToolsJsonCanBeAnalyzed()
        {
            var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some-global-tool" />""");
            await RunAsync(path =>
                [
                    "analyze",
                    "--repo-root",
                    path,
                    "--discovery-file-path",
                    Path.Join(path, "discovery.json"),
                    "--dependency-file-path",
                    Path.Join(path, "some-global-tool.json"),
                    "--analysis-folder-path",
                    Path.Join(path, AnalyzeWorker.AnalysisDirectoryName),
                    "--verbose",
                ],
                packages:
                [
                    MockNuGetPackage.CreateDotNetToolPackage("some-global-tool", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                    MockNuGetPackage.CreateDotNetToolPackage("some-global-tool", "1.1.0", "net8.0", additionalMetadata: [repoMetadata]),
                ],
                dependencyName: "some-global-tool",
                initialFiles:
                [
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "some-global-tool": {
                              "version": "1.0.0",
                              "commands": [
                                "some-global-tool"
                              ]
                            }
                          }
                        }
                        """),
                    ("discovery.json", """
                        {
                          "Path": "",
                          "IsSuccess": true,
                          "Projects": [],
                          "DotNetToolsJson": {
                            "FilePath": ".config/dotnet-tools.json",
                            "IsSuccess": true,
                            "Dependencies": [
                              {
                                "Name": "some-global-tool",
                                "Version": "1.0.0",
                                "Type": "DotNetTool",
                                "EvaluationResult": null,
                                "TargetFrameworks": null,
                                "IsDevDependency": false,
                                "IsDirect": false,
                                "IsTransitive": false,
                                "IsOverride": false,
                                "IsUpdate": false,
                                "InfoUrl": null
                              }
                            ]
                          }
                        }
                        """),
                    ("some-global-tool.json", """
                        {
                          "Name": "some-global-tool",
                          "Version": "1.0.0",
                          "IsVulnerable": false,
                          "IgnoredVersions": [],
                          "Vulnerabilities": []
                        }
                        """),
                ],
                expectedResult: new()
                {
                    UpdatedVersion = "1.1.0",
                    CanUpdate = true,
                    VersionComesFromMultiDependencyProperty = false,
                    UpdatedDependencies =
                    [
                        new Dependency("some-global-tool", "1.1.0", DependencyType.DotNetTool, TargetFrameworks: null, IsDirect: true, InfoUrl: "https://nuget.example.com/some-global-tool")
                    ],
                }
            );
        }

        [Fact]
        public async Task GlobalJsonCanBeAnalyzed()
        {
            var repoMetadata = XElement.Parse("""<repository type="git" url="https://nuget.example.com/some.msbuild.sdk" />""");
            await RunAsync(path =>
                [
                    "analyze",
                    "--repo-root",
                    path,
                    "--discovery-file-path",
                    Path.Join(path, "discovery.json"),
                    "--dependency-file-path",
                    Path.Join(path, "Some.MSBuild.Sdk.json"),
                    "--analysis-folder-path",
                    Path.Join(path, AnalyzeWorker.AnalysisDirectoryName),
                    "--verbose",
                ],
                packages:
                [
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "1.0.0", "net8.0", additionalMetadata: [repoMetadata]),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "1.1.0", "net8.0", additionalMetadata: [repoMetadata]),
                ],
                dependencyName: "Some.MSBuild.Sdk",
                initialFiles:
                [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "8.0.300",
                            "rollForward": "latestPatch"
                          },
                          "msbuild-sdks": {
                            "Some.MSBuild.Sdk": "1.0.0"
                          }
                        }
                        """),
                    ("discovery.json", """
                        {
                          "Path": "",
                          "IsSuccess": true,
                          "Projects": [],
                          "GlobalJson": {
                            "FilePath": "global.json",
                            "IsSuccess": true,
                            "Dependencies": [
                              {
                                "Name": "Some.MSBuild.Sdk",
                                "Version": "1.0.0",
                                "Type": "MSBuildSdk",
                                "EvaluationResult": null,
                                "TargetFrameworks": null,
                                "IsDevDependency": false,
                                "IsDirect": false,
                                "IsTransitive": false,
                                "IsOverride": false,
                                "IsUpdate": false,
                                "InfoUrl": null
                              }
                            ]
                          }
                        }
                        """),
                    ("Some.MSBuild.Sdk.json", """
                        {
                          "Name": "Some.MSBuild.Sdk",
                          "Version": "1.0.0",
                          "IsVulnerable": false,
                          "IgnoredVersions": [],
                          "Vulnerabilities": []
                        }
                        """),
                ],
                expectedResult: new()
                {
                    UpdatedVersion = "1.1.0",
                    CanUpdate = true,
                    VersionComesFromMultiDependencyProperty = false,
                    UpdatedDependencies =
                    [
                        new Dependency("Some.MSBuild.Sdk", "1.1.0", DependencyType.MSBuildSdk, TargetFrameworks: null, IsDirect: true, InfoUrl: "https://nuget.example.com/some.msbuild.sdk")
                    ],
                }
            );
        }

        private static async Task RunAsync(Func<string, string[]> getArgs, string dependencyName, TestFile[] initialFiles, ExpectedAnalysisResult expectedResult, MockNuGetPackage[]? packages = null)
        {
            var actualResult = await RunAnalyzerAsync(dependencyName, initialFiles, async path =>
            {
                var sb = new StringBuilder();
                var writer = new StringWriter(sb);

                var originalOut = Console.Out;
                var originalErr = Console.Error;
                Console.SetOut(writer);
                Console.SetError(writer);

                try
                {
                    await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, path);
                    var args = getArgs(path);
                    var result = await Program.Main(args);
                    if (result != 0)
                    {
                        throw new Exception($"Program exited with code {result}.\nOutput:\n\n{sb}");
                    }
                }
                finally
                {
                    Console.SetOut(originalOut);
                    Console.SetError(originalErr);
                }
            });

            ValidateAnalysisResult(expectedResult, actualResult);
        }
    }
}
