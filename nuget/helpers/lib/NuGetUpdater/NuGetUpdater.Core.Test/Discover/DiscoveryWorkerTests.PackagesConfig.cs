using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class PackagesConfig : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversDependencies()
        {
            await TestDiscoveryAsync(
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Package.A", "1.0.0", "net46"),
                    MockNuGetPackage.CreateSimplePackage("Package.B", "2.0.0", "net46"),
                ],
                workspacePath: "",
                files: [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Package.A" version="1.0.0" targetFramework="net46" />
                          <package id="Package.B" version="2.0.0" targetFramework="net46" />
                        </packages>
                        """),
                    ("myproj.csproj", """
                        <Project>
                          <PropertyGroup>
                            <TargetFramework>net46</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    FilePath = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Properties = [
                                new("TargetFramework", "net46", "myproj.csproj"),
                            ],
                            TargetFrameworks = ["net46"],
                            Dependencies = [
                                new("Microsoft.NETFramework.ReferenceAssemblies", "1.0.3", DependencyType.Unknown, TargetFrameworks: ["net46"], IsTransitive: true),
                                new("Package.A", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Package.B", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                            ],
                        }
                    ],
                }
            );
        }
    }
}
