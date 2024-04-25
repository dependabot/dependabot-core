using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class GlobalJson : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversDependencies()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                files: [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "2.2.104"
                          },
                          "msbuild-sdks": {
                            "Microsoft.Build.Traversal": "1.0.45"
                          }
                        }
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    GlobalJson = new()
                    {
                        FilePath = "global.json",
                        Dependencies = [
                            new("Microsoft.NET.Sdk", "2.2.104", DependencyType.MSBuildSdk),
                            new("Microsoft.Build.Traversal", "1.0.45", DependencyType.MSBuildSdk),
                        ]
                    },
                    ExpectedProjectCount = 0,
                });
        }

        [Fact]
        public async Task ReportsFailure()
        {
            await TestDiscoveryAsync(
                workspacePath: "",
                files: [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "2.2.104",
                          },
                          "msbuild-sdks": {
                            "Microsoft.Build.Traversal": "1.0.45"
                          }
                        }
                        """),
                ],
                expectedResult: new()
                {
                    Path = "",
                    GlobalJson = new()
                    {
                        FilePath = "global.json",
                        IsSuccess = false,
                        ExpectedDependencyCount = 0,
                    },
                    ExpectedProjectCount = 0,
                });
        }
    }
}
