using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.DependencySolver;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;
using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class FileWriterWorkerTests : TestBase
{
    [Fact]
    public async Task EndToEnd_ProjectReference()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="2.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_ProjectReference_ThroughProjectReferences()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectName: "src/project.csproj",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                  <ItemGroup>
                    <ProjectReference Include="..\common\common.csproj" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("common/common.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="2.0.0" />
                  </ItemGroup>
                  <ItemGroup>
                    <ProjectReference Include="..\common\common.csproj" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                ("common/common.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net9.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/common/common.csproj", "/src/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_ProjectReference_NotInRoot()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectName: "src/project.csproj",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <Import Project="Misc.props" />
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("src/Misc.props", """
                    <Project />
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <Import Project="Misc.props" />
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="2.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/src/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_ProjectReferenceWithPackageLockJson()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("packages.lock.json", "{}")
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="2.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/project.csproj"] }
            ],
            additionalChecks: (repoContentsPath) =>
            {
                var lockFilePath = Path.Join(repoContentsPath.FullName, "packages.lock.json");
                var lockFileContent = File.ReadAllText(lockFilePath);
                Assert.Contains("\"resolved\": \"2.0.0\"", lockFileContent);
            }
        );
    }

    [Fact]
    public async Task EndToEnd_ProjectReference_PinnedTransitiveDependency()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Transitive.Dependency",
            oldDependencyVersion: "2.0.0",
            newDependencyVersion: "3.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0", [(null, [("Transitive.Dependency", "2.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "2.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "3.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                    <PackageReference Include="Transitive.Dependency" Version="3.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: [
                new PinnedUpdate() { DependencyName = "Transitive.Dependency", NewVersion = NuGetVersion.Parse("3.0.0"), UpdatedFiles = ["/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_ProjectReference_PinnedTransitiveDependency_With_CentralPackageTransitivePinningEnabled()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Transitive.Dependency",
            oldDependencyVersion: "2.0.0",
            newDependencyVersion: "3.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("Directory.Build.props", "<Project />"),
                ("Directory.Build.targets", "<Project />"),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0", [(null, [("Transitive.Dependency", "2.0.0")])]),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "2.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "3.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedOperations: [
                new PinnedUpdate() { DependencyName = "Transitive.Dependency", NewVersion = NuGetVersion.Parse("3.0.0"), UpdatedFiles = ["/Directory.Packages.props"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_PackagesConfig()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Dependency">
                      <HintPath>packages\Some.Dependency.1.0.0\lib\net45\Some.Dependency.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            additionalFiles: [
                ("packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Dependency" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net45"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Dependency">
                      <HintPath>packages\Some.Dependency.2.0.0\lib\net45\Some.Dependency.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedAdditionalFiles: [
                ("packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Dependency" version="2.0.0" targetFramework="net45" />
                    </packages>
                    """)
            ],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/packages.config", "/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_PackagesConfig_AndPackageReference()
    {
        // project is directly changed
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Dependency">
                      <HintPath>packages\Some.Dependency.1.0.0\lib\net45\Some.Dependency.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            additionalFiles: [
                ("packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Dependency" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("Directory.Build.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net45"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Dependency">
                      <HintPath>packages\Some.Dependency.2.0.0\lib\net45\Some.Dependency.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedAdditionalFiles: [
                ("packages.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Dependency" version="2.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("Directory.Build.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/Directory.Build.props", "/packages.config", "/project.csproj"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_DotNetTools_UpdatePerformed()
    {
        // project is unchanged but `.config/dotnet-tools.json` is updated
        await TestAsync(
            dependencyName: "Some.DotNet.Tool",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "some.dotnet.tool": {
                          "version": "1.0.0",
                          "commands": [
                            "some.dotnet.tool"
                          ]
                        },
                        "some-other-tool": {
                          "version": "2.1.3",
                          "commands": [
                            "some-other-tool"
                          ]
                        }
                      }
                    }
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "some.dotnet.tool": {
                          "version": "1.1.0",
                          "commands": [
                            "some.dotnet.tool"
                          ]
                        },
                        "some-other-tool": {
                          "version": "2.1.3",
                          "commands": [
                            "some-other-tool"
                          ]
                        }
                      }
                    }
                    """)],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.DotNet.Tool", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("1.1.0"), UpdatedFiles = ["/.config/dotnet-tools.json"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_DotNetTools_NoUpdatePerformed()
    {
        // `.config/dotnet-tools.json` doesn't have the requested tool, so no update is performed
        await TestAsync(
            dependencyName: "Some.DotNet.Tool",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "some-other-tool": {
                          "version": "2.1.3",
                          "commands": [
                            "some-other-tool"
                          ]
                        }
                      }
                    }
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateDotNetToolPackage("Some.DotNet.Tool", "1.1.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                (".config/dotnet-tools.json", """
                    {
                      "version": 1,
                      "isRoot": true,
                      "tools": {
                        "some-other-tool": {
                          "version": "2.1.3",
                          "commands": [
                            "some-other-tool"
                          ]
                        }
                      }
                    }
                    """)],
            expectedOperations: []
        );
    }

    [Fact]
    public async Task EndToEnd_GlobalJson()
    {
        // project is unchanged but `global.json` is updated
        await TestAsync(
            dependencyName: "Some.MSBuild.Sdk",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [
                ("global.json", """
                    {
                      "sdk": {
                        "version": "6.0.405",
                        "rollForward": "latestPatch"
                      },
                      "msbuild-sdks": {
                        "Some.MSBuild.Sdk": "1.0.0"
                      }
                    }
                    """)
            ],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "1.0.0"),
                MockNuGetPackage.CreateMSBuildSdkPackage("Some.MSBuild.Sdk", "1.1.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [
                ("global.json", """
                    {
                      "sdk": {
                        "version": "6.0.405",
                        "rollForward": "latestPatch"
                      },
                      "msbuild-sdks": {
                        "Some.MSBuild.Sdk": "1.1.0"
                      }
                    }
                    """)],
            expectedOperations: [
                new DirectUpdate() { DependencyName = "Some.MSBuild.Sdk", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("1.1.0"), UpdatedFiles = ["/global.json"] }
            ]
        );
    }

    [Fact]
    public async Task EndToEnd_FileEditUnsuccessful_NoFileEditsRetained()
    {
        // the file writer has been interrupted to make no edits and report failure
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: null, // use real worker
            dependencySolver: null, // use real worker
            fileWriter: new TestFileWriterReturnsConstantResult(false), // always report failure to edit files
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: []
        );
    }

    [Fact]
    public async Task EndToEnd_FinalDependencyResolutionUnsuccessful_NoFileEditsRetained()
    {
        // the discovery worker has been interrupted to report the update didn't produce the desired result
        // no file edits will be preserved
        var discoveryRequestCount = 0;
        await TestAsync(
            dependencyName: "Some.Dependency",
            oldDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: [],
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net9.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Dependency", "2.0.0", "net9.0"),
            ],
            discoveryWorker: new TestDiscoveryWorker(args =>
            {
                discoveryRequestCount++;
                var result = discoveryRequestCount switch
                {
                    // initial request, report 1.0.0
                    1 => new WorkspaceDiscoveryResult()
                    {
                        Path = "/",
                        Projects = [
                            new ProjectDiscoveryResult()
                            {
                                FilePath = "project.csproj",
                                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                                TargetFrameworks = ["net9.0"],
                                AdditionalFiles = [],
                                ImportedFiles = [],
                                ReferencedProjectPaths = []
                            }
                        ]
                    },
                    // post-edit request, report 1.0.0 again, indicating the file edits didn't produce the desired result
                    2 => new WorkspaceDiscoveryResult()
                    {
                        Path = "/",
                        Projects = [
                            new ProjectDiscoveryResult()
                            {
                                FilePath = "project.csproj",
                                Dependencies = [new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference)],
                                TargetFrameworks = ["net9.0"],
                                AdditionalFiles = [],
                                ImportedFiles = [],
                                ReferencedProjectPaths = []
                            }
                        ]
                    },
                    _ => throw new NotSupportedException($"Didn't expect {discoveryRequestCount} discovery requests"),
                };
                return Task.FromResult(result);
            }),
            dependencySolver: null, // use real worker
            fileWriter: null, // use real worker
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Dependency" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedAdditionalFiles: [],
            expectedOperations: []
        );
    }

    private static async Task TestAsync(
        string dependencyName,
        string oldDependencyVersion,
        string newDependencyVersion,
        string projectContents,
        (string name, string contents)[] additionalFiles,
        IDiscoveryWorker? discoveryWorker,
        IDependencySolver? dependencySolver,
        IFileWriter? fileWriter,
        string expectedProjectContents,
        (string name, string contents)[] expectedAdditionalFiles,
        UpdateOperationBase[] expectedOperations,
        string projectName = "project.csproj",
        MockNuGetPackage[]? packages = null,
        ExperimentsManager? experimentsManager = null,
        Action<DirectoryInfo>? additionalChecks = null
    )
    {
        // arrange
        var allFiles = new List<(string Path, string Contents)>() { (projectName, projectContents) };
        allFiles.AddRange(additionalFiles);
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync([.. allFiles]);
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDir.DirectoryPath);

        var jobId = "TEST-JOB-ID";
        var logger = new TestLogger();
        experimentsManager ??= new ExperimentsManager() { UseDirectDiscovery = true };
        discoveryWorker ??= new DiscoveryWorker(jobId, experimentsManager, logger);
        var repoContentsPath = new DirectoryInfo(tempDir.DirectoryPath);
        var projectPath = new FileInfo(Path.Combine(tempDir.DirectoryPath, projectName));
        dependencySolver ??= new MSBuildDependencySolver(repoContentsPath, projectPath, experimentsManager, logger);
        fileWriter ??= new XmlFileWriter(logger);

        var fileWriterWorker = new FileWriterWorker(discoveryWorker, dependencySolver, fileWriter, logger);

        // act
        var actualUpdateOperations = await fileWriterWorker.RunAsync(
            repoContentsPath,
            projectPath,
            dependencyName,
            NuGetVersion.Parse(oldDependencyVersion),
            NuGetVersion.Parse(newDependencyVersion)
        );

        // assert
        var actualUpdateOperationsJson = actualUpdateOperations.Select(o => JsonSerializer.Serialize(o, RunWorker.SerializerOptions)).ToArray();
        var expectedUpdateOperationsJson = expectedOperations.Select(o => JsonSerializer.Serialize(o, RunWorker.SerializerOptions)).ToArray();
        AssertEx.Equal(expectedUpdateOperationsJson, actualUpdateOperationsJson);

        var expectedFiles = new List<(string Path, string Contents)>() { (projectName, expectedProjectContents) };
        expectedFiles.AddRange(expectedAdditionalFiles);
        foreach (var (path, expectedContents) in expectedFiles)
        {
            var fullPath = Path.Join(tempDir.DirectoryPath, path);
            var actualContents = await File.ReadAllTextAsync(fullPath);
            Assert.Equal(expectedContents.Replace("\r", ""), actualContents.Replace("\r", ""));
        }

        additionalChecks?.Invoke(repoContentsPath);
    }
}
