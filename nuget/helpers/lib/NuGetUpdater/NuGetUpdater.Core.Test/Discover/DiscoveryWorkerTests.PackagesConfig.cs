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
                          <package id="WebActivatorEx" version="2.1.0" targetFramework="net46"></package>
                        </packages>
                        """),
                    ("myproj.csproj", """
                        <Project>
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
                            Dependencies = [
                                new("Microsoft.CodeDom.Providers.DotNetCompilerPlatform", "1.0.0", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("Microsoft.Net.Compilers", "1.0.1", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("Microsoft.Web.Infrastructure", "1.0.0.0", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("Microsoft.Web.Xdt", "2.1.1", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("Newtonsoft.Json", "8.0.3", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("NuGet.Core", "2.11.1", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("NuGet.Server", "2.11.2", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("RouteMagic", "1.3", DependencyType.PackagesConfig, TargetFrameworks: []),
                                new("WebActivatorEx", "2.1.0", DependencyType.PackagesConfig, TargetFrameworks: []),
                            ],
                        }
                    ],
                });
        }
    }
}
