using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class DotNetToolsJson : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversDependencies()
        {
            await TestDiscoveryAsync(
                packages: [],
                workspacePath: "",
                files: [
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "botsay": {
                              "version": "1.0.0",
                              "commands": [
                                "botsay"
                              ]
                            },
                            "dotnetsay": {
                              "version": "1.0.0",
                              "commands": [
                                "dotnetsay"
                              ]
                            }
                          }
                        }
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    DotNetToolsJson = new()
                    {
                        FilePath = ".config/dotnet-tools.json",
                        Dependencies = [
                            new("botsay", "1.0.0", DependencyType.DotNetTool),
                            new("dotnetsay", "1.0.0", DependencyType.DotNetTool),
                        ]
                    },
                    ExpectedProjectCount = 0,
                }
            );
        }

        [Fact]
        public async Task DiscoversDependenciesTrailingComma()
        {
            await TestDiscoveryAsync(
                packages: [],
                workspacePath: "",
                files: [
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "botsay": {
                              "version": "1.0.0",
                              "commands": [
                                "botsay"
                              ],
                            },
                            "dotnetsay": {
                              "version": "1.0.0",
                              "commands": [
                                "dotnetsay"
                              ],
                            }
                          }
                        }
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    DotNetToolsJson = new()
                    {
                        FilePath = ".config/dotnet-tools.json",
                        Dependencies = [
                            new("botsay", "1.0.0", DependencyType.DotNetTool),
                            new("dotnetsay", "1.0.0", DependencyType.DotNetTool),
                        ]
                    },
                    ExpectedProjectCount = 0,
                }
            );
        }

        [Fact]
        public async Task ReportsFailure()
        {
            await TestDiscoveryAsync(
                packages: [],
                workspacePath: "",
                files: [
                    (".config/dotnet-tools.json", """
                        {
                          "version": 1,
                          "isRoot": true,
                          "tools": {
                            "botsay": {
                              "version": "1.0.0",
                              "commands": [
                                "botsay"
                              ],
                            },
                            "dotnetsay": {
                              "version": "1.0.0",
                              "commands": [
                                "dotnetsay"
                              ]
                            }
                          } INVALID JSON
                        }
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    DotNetToolsJson = new()
                    {
                        FilePath = ".config/dotnet-tools.json",
                        IsSuccess = false,
                        ExpectedDependencyCount = 0,
                    },
                    ExpectedProjectCount = 0,
                }
            );
        }
    }
}
