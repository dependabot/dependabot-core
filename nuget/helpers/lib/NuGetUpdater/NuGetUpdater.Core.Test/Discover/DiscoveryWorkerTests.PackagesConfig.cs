using System.Collections.Immutable;

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
                workspacePath: "",
                files: [
                    ("packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Microsoft.CodeDom.Providers.DotNetCompilerPlatform" version="1.0.0" targetFramework="net46" />
                          <package id="Microsoft.Net.Compilers" version="1.0.1" targetFramework="net46" developmentDependency="true" />
                          <package id="Microsoft.Web.Infrastructure" version="1.0.0.0" targetFramework="net46" />
                          <package id="Microsoft.Web.Xdt" version="2.1.1" targetFramework="net46" />
                          <package id="Newtonsoft.Json" version="8.0.3" allowedVersions="[8,10)" targetFramework="net46" />
                          <package id="NuGet.Core" version="2.11.1" targetFramework="net46" />
                          <package id="NuGet.Server" version="2.11.2" targetFramework="net46" />
                          <package id="RouteMagic" version="1.3" targetFramework="net46" />
                          <package id="WebActivatorEx" version="2.1.0" targetFramework="net46" />
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
                    Path = "",
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
                                new("Microsoft.CodeDom.Providers.DotNetCompilerPlatform", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Microsoft.Net.Compilers", "1.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Microsoft.Web.Infrastructure", "1.0.0.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Microsoft.Web.Xdt", "2.1.1", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("Newtonsoft.Json", "8.0.3", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("NuGet.Core", "2.11.1", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("NuGet.Server", "2.11.2", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("RouteMagic", "1.3", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                                new("WebActivatorEx", "2.1.0", DependencyType.PackagesConfig, TargetFrameworks: ["net46"]),
                            ],
                        }
                    ],
                });
        }
    }
}
