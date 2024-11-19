using Xunit;

namespace NuGetUpdater.Core.Test.Discover;

public partial class DiscoveryWorkerTests
{
    public class PackagesConfig : DiscoveryWorkerTestBase
    {
        [Fact]
        public async Task DiscoversDependencies_DirectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = true },
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
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net46</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Properties = [
                                new("TargetFramework", "net46", "myproj.csproj")
                            ],
                            TargetFrameworks = ["net46"],
                            Dependencies = [
                                new("Package.A", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Package.B", "2.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                            ],
                        }
                    ],
                }
            );
        }

        [Fact]
        public async Task DiscoversDependencies_TemporaryProjectDiscovery()
        {
            await TestDiscoveryAsync(
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = false },
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
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net46</TargetFramework>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedResult: new()
                {
                    Path = "",
                    Projects = [
                        new()
                        {
                            FilePath = "myproj.csproj",
                            Properties = [new("TargetFramework", "net46", "myproj.csproj")],
                            TargetFrameworks = ["net46"],
                            Dependencies = [
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
