using System.Collections.Immutable;
using System.Net;
using System.Net.Mail;
using System.Text;
using System.Text.Json;

using NuGet;
using NuGet.Versioning;

using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class PackagesConfigUpdaterTests : TestBase
{
    [Fact]
    public async Task UpdateSingleDependencyInPackagesConfig()
    {
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
            ],
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
                    <Reference Include="Some.Package, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
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
                    <Reference Include="Some.Package">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdateSingleDependencyInPackagesConfig_ReferenceHasNoAssemblyVersion()
    {
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
            ],
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
                    <Reference Include="Some.Package">
                        <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                        <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
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
                    <Reference Include="Some.Package">
                        <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                        <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdateDependency_NoAssembliesAndContentDirectoryDiffersByCase()
    {
        await TestAsync("Package.With.No.Assembly", "1.0.0", "1.1.0",
            packages: [
                // this package is expected to have a directory named `content`, but here it differs by case as `Content`
                new MockNuGetPackage("Package.With.No.Assembly", "1.0.0", Files: [("Content/some-content.txt", [])]),
                new MockNuGetPackage("Package.With.No.Assembly", "1.1.0", Files: [("Content/some-content.txt", [])]),
            ],
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Package.With.No.Assembly" version="1.0.0" targetFramework="net45" />
                </packages>
                """,
            expectedProjectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Package.With.No.Assembly" version="1.1.0" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Package.With.No.Assembly", NewVersion = NuGetVersion.Parse("1.1.0"), UpdatedFiles = ["/project.csproj", "/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdatePackageWithTargetsFileWhereProjectUsesBackslashes()
    {
        // The bug that caused this test to be written did not repro on Windows.  The reason is that the packages
        // directory is determined to be `..\packages`, but the backslash was retained.  Later when packages were
        // restored to that location, a directory with a name like `..?packages` would be created which didn't
        // match the <Import> element's path of "..\packages\..." that had no `Condition="Exists(path)"` attribute.
        await TestAsync("Some.Package", "1.0.0", "2.0.0",
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net45"),
                new MockNuGetPackage("Package.With.Targets", "1.0.0", Files: [("build/SomeFile.targets", Encoding.UTF8.GetBytes("<Project />"))]),
            ],
            projectPath: "src/project.csproj",
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
                    <Reference Include="Some.Package">
                      <HintPath>..\packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="..\packages\Package.With.Targets.1.0.0\build\SomeFile.targets" />
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigPath: "src/packages.config",
            packagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Package.With.Targets" version="1.0.0" targetFramework="net45" />
                  <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                </packages>
                """,
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
                    <Reference Include="Some.Package">
                      <HintPath>..\packages\Some.Package.2.0.0\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="..\packages\Package.With.Targets.1.0.0\build\SomeFile.targets" />
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Package.With.Targets" version="1.0.0" targetFramework="net45" />
                  <package id="Some.Package" version="2.0.0" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/src/project.csproj", "/src/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdatePackagesConfigWithNonStandardLocationOfPackagesDirectory()
    {
        // update Some.Package from 7.0.1 to 13.0.1 with the actual assembly in a non-standard location
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
            ],
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
                    <Reference Include="Some.Package">
                      <HintPath>some-non-standard-location\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
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
                    <Reference Include="Some.Package">
                      <HintPath>some-non-standard-location\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdateBindingRedirectInAppConfig_UnrelatedBindingRedirectIsUntouched()
    {
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0"),
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0"),
                MockNuGetPackage.CreatePackageWithAssembly("Unrelated.Package", "1.2.3", "net45","1.2.0.0"),
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=7.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Unrelated.Package, Version=1.2.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Unrelated.Package.1.2.3\lib\net45\Unrelated.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFiles:
            [
                ("app.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-7.0.0.0" newVersion="7.0.0.0" />
                          </dependentAssembly>
                          <dependentAssembly>
                            <assemblyIdentity name="Unrelated.Package" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=13.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Unrelated.Package, Version=1.2.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Unrelated.Package.1.2.3\lib\net45\Unrelated.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFilesExpected:
            [
                ("app.config", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-13.0.0.0" newVersion="13.0.0.0" />
                          </dependentAssembly>
                          <dependentAssembly>
                            <assemblyIdentity name="Unrelated.Package" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config", "/app.config"] },
            ]
        );
    }

    [Fact]
    public async Task BindingRedirectIsAddedForUpdatedPackage()
    {
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0"),
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0"),
                MockNuGetPackage.CreatePackageWithAssembly("Unrelated.Package", "1.2.3", "net45","1.2.0.0"),
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=7.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Unrelated.Package, Version=1.2.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Unrelated.Package.1.2.3\lib\net45\Unrelated.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFiles: [
                ("app.config", """
                    <configuration>
                      <runtime />
                    </configuration>
                    """)
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=13.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Unrelated.Package, Version=1.2.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Unrelated.Package.1.2.3\lib\net45\Unrelated.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFilesExpected: [
                ("app.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-13.0.0.0" newVersion="13.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config", "/app.config"] },
            ]
        );
    }

    // the xml can take various shapes and they're all formatted, so we need very specific values here
    [Theory]
    [InlineData("<Content Include=\"web.config\" />")]
    [InlineData("<Content Include=\"web.config\">\n    </Content>")]
    [InlineData("<Content Include=\"web.config\">\n      <SubType>Designer</SubType>\n    </Content>")]
    public async Task UpdateBindingRedirectInWebConfig(string webConfigXml)
    {
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0"),
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0"),
            ],
            projectContents: $$"""
                <Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <PropertyGroup>
                    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
                    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
                    <ProductVersion>
                    </ProductVersion>
                    <SchemaVersion>2.0</SchemaVersion>
                    <ProjectGuid>ac83fc79-b637-445b-acb0-9be238ad077f</ProjectGuid>
                    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
                    <OutputType>Library</OutputType>
                    <AppDesignerFolder>Properties</AppDesignerFolder>
                    <RootNamespace>TestProject</RootNamespace>
                    <AssemblyName>TestProject</AssemblyName>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
                    <DebugSymbols>true</DebugSymbols>
                    <DebugType>full</DebugType>
                    <Optimize>false</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>DEBUG;TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
                    <DebugType>pdbonly</DebugType>
                    <Optimize>true</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <ItemGroup>
                    <Reference Include="Microsoft.CSharp" />
                    <Reference Include="Some.Package, Version=7.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="System.Web.DynamicData" />
                    <Reference Include="System.Web.Entity" />
                    <Reference Include="System.Web.ApplicationServices" />
                    <Reference Include="System" />
                    <Reference Include="System.Data" />
                    <Reference Include="System.Core" />
                    <Reference Include="System.Data.DataSetExtensions" />
                    <Reference Include="System.Web.Extensions" />
                    <Reference Include="System.Xml.Linq" />
                    <Reference Include="System.Drawing" />
                    <Reference Include="System.Web" />
                    <Reference Include="System.Xml" />
                    <Reference Include="System.Configuration" />
                    <Reference Include="System.Web.Services" />
                    <Reference Include="System.EnterpriseServices" />
                  </ItemGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                    {{webConfigXml}}
                    <Content Include="web.Debug.config">
                      <DependentUpon>web.config</DependentUpon>
                    </Content>
                    <Content Include="web.Release.config">
                      <DependentUpon>web.config</DependentUpon>
                    </Content>
                  </ItemGroup>
                  <ItemGroup>
                    <Compile Include="Properties\AssemblyInfo.cs" />
                  </ItemGroup>
                  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
                  <Import Project="$(VSToolsPath)\WebApplications\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
                  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
                      Other similar extension points exist, see Microsoft.Common.targets.
                  <Target Name="BeforeBuild">
                  </Target>
                  <Target Name="AfterBuild">
                  </Target>
                  -->
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFiles:
            [
                ("web.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-7.0.0.0" newVersion="7.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
            expectedProjectContents: $$"""
                <Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <PropertyGroup>
                    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
                    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
                    <ProductVersion>
                    </ProductVersion>
                    <SchemaVersion>2.0</SchemaVersion>
                    <ProjectGuid>ac83fc79-b637-445b-acb0-9be238ad077f</ProjectGuid>
                    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
                    <OutputType>Library</OutputType>
                    <AppDesignerFolder>Properties</AppDesignerFolder>
                    <RootNamespace>TestProject</RootNamespace>
                    <AssemblyName>TestProject</AssemblyName>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
                    <DebugSymbols>true</DebugSymbols>
                    <DebugType>full</DebugType>
                    <Optimize>false</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>DEBUG;TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
                    <DebugType>pdbonly</DebugType>
                    <Optimize>true</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <ItemGroup>
                    <Reference Include="Microsoft.CSharp" />
                    <Reference Include="Some.Package, Version=13.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="System.Web.DynamicData" />
                    <Reference Include="System.Web.Entity" />
                    <Reference Include="System.Web.ApplicationServices" />
                    <Reference Include="System" />
                    <Reference Include="System.Data" />
                    <Reference Include="System.Core" />
                    <Reference Include="System.Data.DataSetExtensions" />
                    <Reference Include="System.Web.Extensions" />
                    <Reference Include="System.Xml.Linq" />
                    <Reference Include="System.Drawing" />
                    <Reference Include="System.Web" />
                    <Reference Include="System.Xml" />
                    <Reference Include="System.Configuration" />
                    <Reference Include="System.Web.Services" />
                    <Reference Include="System.EnterpriseServices" />
                  </ItemGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                    {{webConfigXml}}
                    <Content Include="web.Debug.config">
                      <DependentUpon>web.config</DependentUpon>
                    </Content>
                    <Content Include="web.Release.config">
                      <DependentUpon>web.config</DependentUpon>
                    </Content>
                  </ItemGroup>
                  <ItemGroup>
                    <Compile Include="Properties\AssemblyInfo.cs" />
                  </ItemGroup>
                  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
                  <Import Project="$(VSToolsPath)\WebApplications\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
                  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
                      Other similar extension points exist, see Microsoft.Common.targets.
                  <Target Name="BeforeBuild">
                  </Target>
                  <Target Name="AfterBuild">
                  </Target>
                  -->
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFilesExpected: [
                ("web.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-13.0.0.0" newVersion="13.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config", "/web.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdateBindingRedirect_DuplicateRedirectsForTheSameAssemblyAreRemoved()
    {
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0"),
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0"),
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=7.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFiles: [
                ("app.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-7.0.0.0" newVersion="7.0.0.0" />
                          </dependentAssembly>
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-7.0.0.0" newVersion="7.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=13.0.0.0, Culture=neutral, PublicKeyToken=null">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFilesExpected: [
                ("app.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="null" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-13.0.0.0" newVersion="13.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config", "/app.config"] },
            ]
        );
    }

    [Fact]
    public async Task UpdateBindingRedirect_ExistingRedirectForAssemblyPublicKeyTokenDiffersByCase()
    {
        // Generated using "sn -k keypair.snk && sn -p keypair.snk public.snk" then converting public.snk to base64
        // https://learn.microsoft.com/en-us/dotnet/standard/assembly/create-public-private-key-pair
        var assemblyStrongNamePublicKey = Convert.FromBase64String(
          "ACQAAASAAACUAAAABgIAAAAkAABSU0ExAAQAAAEAAQAJJW4hmKpxa9pU0JPDvJ9KqjvfQuMUovGtFjkZ9b0i1KQ/7kqEOjW3Va0eGpU7Kz0qHp14iYQ3SsMzBZU3mZ2Ezeqg+dCVuDk7o2lp++4m1FstHsebtXBetyOzWkneo+3iKSzOQ7bOXj2s5M9umqRPk+yj0ZBILf+HvfAd07iIuQ=="
        ).ToImmutableArray();

        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0", assemblyPublicKey: assemblyStrongNamePublicKey),
                MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0", assemblyPublicKey: assemblyStrongNamePublicKey),
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=7.0.0.0, Culture=neutral, PublicKeyToken=13523fc3be375af1">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFiles: [
                ("app.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="13523FC3BE375AF1" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-7.0.0.0" newVersion="7.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
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
                    <None Include="app.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Some.Package, Version=13.0.0.0, Culture=neutral, PublicKeyToken=13523fc3be375af1">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFilesExpected: [
                ("app.config", """
                    <configuration>
                      <runtime>
                        <assemblyBinding xmlns="urn:schemas-microsoft-com:asm.v1">
                          <dependentAssembly>
                            <assemblyIdentity name="Some.Package" publicKeyToken="13523FC3BE375AF1" culture="neutral" />
                            <bindingRedirect oldVersion="0.0.0.0-13.0.0.0" newVersion="13.0.0.0" />
                          </dependentAssembly>
                        </assemblyBinding>
                      </runtime>
                    </configuration>
                    """)
            ],
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config", "/app.config"] },
            ]
        );
    }

    [Fact]
    public async Task PackagesConfigUpdateCanHappenEvenWithMismatchedVersionNumbers()
    {
        // `packages.config` reports `7.0.1` and that's what we want to update, but the project file has a mismatch that's corrected
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
            ],
            projectContents: """
                <Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <PropertyGroup>
                    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
                    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
                    <ProductVersion>
                    </ProductVersion>
                    <SchemaVersion>2.0</SchemaVersion>
                    <ProjectGuid>ac83fc79-b637-445b-acb0-9be238ad077f</ProjectGuid>
                    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
                    <OutputType>Library</OutputType>
                    <AppDesignerFolder>Properties</AppDesignerFolder>
                    <RootNamespace>TestProject</RootNamespace>
                    <AssemblyName>TestProject</AssemblyName>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
                    <DebugSymbols>true</DebugSymbols>
                    <DebugType>full</DebugType>
                    <Optimize>false</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>DEBUG;TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
                    <DebugType>pdbonly</DebugType>
                    <Optimize>true</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <ItemGroup>
                    <Reference Include="Microsoft.CSharp" />
                    <Reference Include="Some.Package, Version=6.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Some.Package.6.0.8\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="System.Web.DynamicData" />
                    <Reference Include="System.Web.Entity" />
                    <Reference Include="System.Web.ApplicationServices" />
                    <Reference Include="System" />
                    <Reference Include="System.Data" />
                    <Reference Include="System.Core" />
                    <Reference Include="System.Data.DataSetExtensions" />
                    <Reference Include="System.Web.Extensions" />
                    <Reference Include="System.Xml.Linq" />
                    <Reference Include="System.Drawing" />
                    <Reference Include="System.Web" />
                    <Reference Include="System.Xml" />
                    <Reference Include="System.Configuration" />
                    <Reference Include="System.Web.Services" />
                    <Reference Include="System.EnterpriseServices" />
                  </ItemGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Compile Include="Properties\AssemblyInfo.cs" />
                  </ItemGroup>
                  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
                  <Import Project="$(VSToolsPath)\WebApplications\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
                  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
                      Other similar extension points exist, see Microsoft.Common.targets.
                  <Target Name="BeforeBuild">
                  </Target>
                  <Target Name="AfterBuild">
                  </Target>
                  -->
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            expectedProjectContents: """
                <Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <PropertyGroup>
                    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
                    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
                    <ProductVersion>
                    </ProductVersion>
                    <SchemaVersion>2.0</SchemaVersion>
                    <ProjectGuid>ac83fc79-b637-445b-acb0-9be238ad077f</ProjectGuid>
                    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
                    <OutputType>Library</OutputType>
                    <AppDesignerFolder>Properties</AppDesignerFolder>
                    <RootNamespace>TestProject</RootNamespace>
                    <AssemblyName>TestProject</AssemblyName>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
                    <DebugSymbols>true</DebugSymbols>
                    <DebugType>full</DebugType>
                    <Optimize>false</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>DEBUG;TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
                    <DebugType>pdbonly</DebugType>
                    <Optimize>true</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <ItemGroup>
                    <Reference Include="Microsoft.CSharp" />
                    <Reference Include="Some.Package">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="System.Web.DynamicData" />
                    <Reference Include="System.Web.Entity" />
                    <Reference Include="System.Web.ApplicationServices" />
                    <Reference Include="System" />
                    <Reference Include="System.Data" />
                    <Reference Include="System.Core" />
                    <Reference Include="System.Data.DataSetExtensions" />
                    <Reference Include="System.Web.Extensions" />
                    <Reference Include="System.Xml.Linq" />
                    <Reference Include="System.Drawing" />
                    <Reference Include="System.Web" />
                    <Reference Include="System.Xml" />
                    <Reference Include="System.Configuration" />
                    <Reference Include="System.Web.Services" />
                    <Reference Include="System.EnterpriseServices" />
                  </ItemGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Compile Include="Properties\AssemblyInfo.cs" />
                  </ItemGroup>
                  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
                  <Import Project="$(VSToolsPath)\WebApplications\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
                  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
                      Other similar extension points exist, see Microsoft.Common.targets.
                  <Target Name="BeforeBuild">
                  </Target>
                  <Target Name="AfterBuild">
                  </Target>
                  -->
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task WellKnownMissingTargetsFileThatIsExplicitlyImportedDoesNotPreventUpdate()
    {
        // the file `Microsoft.WebApplication.targets` is not present in the test or prod environment, but it is explicitly imported in the project file
        // the supplied `Condition` attribute is always true, so the import will always fail, but it should not prevent the update from happening
        await TestAsync("Some.Package", "7.0.1", "13.0.1",
            packages: [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
            ],
            projectContents: """
                <Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <PropertyGroup>
                    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
                    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
                    <ProductVersion>
                    </ProductVersion>
                    <SchemaVersion>2.0</SchemaVersion>
                    <ProjectGuid>68ed3303-52a0-47b8-a687-3abbb07530da</ProjectGuid>
                    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
                    <OutputType>Library</OutputType>
                    <AppDesignerFolder>Properties</AppDesignerFolder>
                    <RootNamespace>TestProject</RootNamespace>
                    <AssemblyName>TestProject</AssemblyName>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
                    <DebugSymbols>true</DebugSymbols>
                    <DebugType>full</DebugType>
                    <Optimize>false</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>DEBUG;TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
                    <DebugType>pdbonly</DebugType>
                    <Optimize>true</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <ItemGroup>
                    <Reference Include="Microsoft.CSharp" />
                    <Reference Include="Some.Package">
                      <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="System.Web.DynamicData" />
                    <Reference Include="System.Web.Entity" />
                    <Reference Include="System.Web.ApplicationServices" />
                    <Reference Include="System" />
                    <Reference Include="System.Data" />
                    <Reference Include="System.Core" />
                    <Reference Include="System.Data.DataSetExtensions" />
                    <Reference Include="System.Web.Extensions" />
                    <Reference Include="System.Xml.Linq" />
                    <Reference Include="System.Drawing" />
                    <Reference Include="System.Web" />
                    <Reference Include="System.Xml" />
                    <Reference Include="System.Configuration" />
                    <Reference Include="System.Web.Services" />
                    <Reference Include="System.EnterpriseServices" />
                  </ItemGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Compile Include="Properties\AssemblyInfo.cs" />
                  </ItemGroup>
                  <ItemGroup>
                    <ProjectReference Include="other-project\other-project.csproj" />
                  </ItemGroup>
                  <PropertyGroup>
                    <!-- some project files set this property which makes the Microsoft.WebApplication.targets import a few lines down always fail -->
                    <VSToolsPath Condition="'$(VSToolsPath)' == ''">C:\some\path\that\does\not\exist</VSToolsPath>
                  </PropertyGroup>
                  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
                  <Import Project="$(VSToolsPath)\SomeSubPath\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
                  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
                      Other similar extension points exist, see Microsoft.Common.targets.
                  <Target Name="BeforeBuild">
                  </Target>
                  <Target Name="AfterBuild">
                  </Target>
                  -->
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                </packages>
                """,
            additionalFiles: [
                ("other-project/other-project.csproj", """
                    <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <OutputType>Library</OutputType>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <Import Project="$(VSToolsPath)\SomeSubPath\WebApplications\Microsoft.WebApplication.targets" />
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """)
            ],
            expectedProjectContents: """
                <Project ToolsVersion="4.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <PropertyGroup>
                    <Configuration Condition=" '$(Configuration)' == '' ">Debug</Configuration>
                    <Platform Condition=" '$(Platform)' == '' ">AnyCPU</Platform>
                    <ProductVersion>
                    </ProductVersion>
                    <SchemaVersion>2.0</SchemaVersion>
                    <ProjectGuid>68ed3303-52a0-47b8-a687-3abbb07530da</ProjectGuid>
                    <ProjectTypeGuids>{349c5851-65df-11da-9384-00065b846f21};{fae04ec0-301f-11d3-bf4b-00c04f79efbc}</ProjectTypeGuids>
                    <OutputType>Library</OutputType>
                    <AppDesignerFolder>Properties</AppDesignerFolder>
                    <RootNamespace>TestProject</RootNamespace>
                    <AssemblyName>TestProject</AssemblyName>
                    <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Debug|AnyCPU' ">
                    <DebugSymbols>true</DebugSymbols>
                    <DebugType>full</DebugType>
                    <Optimize>false</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>DEBUG;TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <PropertyGroup Condition=" '$(Configuration)|$(Platform)' == 'Release|AnyCPU' ">
                    <DebugType>pdbonly</DebugType>
                    <Optimize>true</Optimize>
                    <OutputPath>bin\</OutputPath>
                    <DefineConstants>TRACE</DefineConstants>
                    <ErrorReport>prompt</ErrorReport>
                    <WarningLevel>4</WarningLevel>
                  </PropertyGroup>
                  <ItemGroup>
                    <Reference Include="Microsoft.CSharp" />
                    <Reference Include="Some.Package">
                      <HintPath>packages\Some.Package.13.0.1\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="System.Web.DynamicData" />
                    <Reference Include="System.Web.Entity" />
                    <Reference Include="System.Web.ApplicationServices" />
                    <Reference Include="System" />
                    <Reference Include="System.Data" />
                    <Reference Include="System.Core" />
                    <Reference Include="System.Data.DataSetExtensions" />
                    <Reference Include="System.Web.Extensions" />
                    <Reference Include="System.Xml.Linq" />
                    <Reference Include="System.Drawing" />
                    <Reference Include="System.Web" />
                    <Reference Include="System.Xml" />
                    <Reference Include="System.Configuration" />
                    <Reference Include="System.Web.Services" />
                    <Reference Include="System.EnterpriseServices" />
                  </ItemGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Compile Include="Properties\AssemblyInfo.cs" />
                  </ItemGroup>
                  <ItemGroup>
                    <ProjectReference Include="other-project\other-project.csproj" />
                  </ItemGroup>
                  <PropertyGroup>
                    <!-- some project files set this property which makes the Microsoft.WebApplication.targets import a few lines down always fail -->
                    <VSToolsPath Condition="'$(VSToolsPath)' == ''">C:\some\path\that\does\not\exist</VSToolsPath>
                  </PropertyGroup>
                  <Import Project="$(MSBuildBinPath)\Microsoft.CSharp.targets" />
                  <Import Project="$(VSToolsPath)\SomeSubPath\Microsoft.WebApplication.targets" Condition="'$(VSToolsPath)' != ''" />
                  <!-- To modify your build process, add your task inside one of the targets below and uncomment it.
                      Other similar extension points exist, see Microsoft.Common.targets.
                  <Target Name="BeforeBuild">
                  </Target>
                  <Target Name="AfterBuild">
                  </Target>
                  -->
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("13.0.1"), UpdatedFiles = ["/project.csproj", "/packages.config"] },
            ]
        );
    }

    [Fact]
    public async Task PackageCanBeUpdatedWhenAnotherInstalledPackageHasBeenDelisted()
    {
        // updating one package (Some.Package) when another installed package (Delisted.Package/5.0.0) has been delisted
        // this test can't be faked with a local package source and requires an HTTP endpoint; the important part is
        // the `"listed": false` in the registration index
        static (int, byte[]) TestHttpHandler(string uriString)
        {
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                "/index.json" => (200, Encoding.UTF8.GetBytes($$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """)),
                "/registrations/delisted.package/index.json" => (200, Encoding.UTF8.GetBytes($$"""
                    {
                        "count": 1,
                        "items": [
                            {
                                "lower": "5.0.0",
                                "upper": "5.0.0",
                                "items": [
                                    {
                                        "catalogEntry": {
                                            "id": "Delisted.Package",
                                            "listed": false,
                                            "version": "5.0.0"
                                        },
                                        "packageContent": "{{baseUrl}}/download/delisted.package/5.0.0/delisted.package.5.0.0.nupkg",
                                    }
                                ]
                            }
                        ]
                    }
                    """)),
                "/registrations/some.package/index.json" => (200, Encoding.UTF8.GetBytes($$"""
                    {
                        "count": 1,
                        "items": [
                            {
                                "lower": "1.0.0",
                                "upper": "2.0.0",
                                "items": [
                                    {
                                        "catalogEntry": {
                                            "id": "Some.Package",
                                            "listed": true,
                                            "version": "1.0.0"
                                        },
                                        "packageContent": "{{baseUrl}}/download/some.package/1.0.0/some.package.1.0.0.nupkg",
                                    },
                                    {
                                        "catalogEntry": {
                                            "id": "Some.Package",
                                            "listed": true,
                                            "version": "2.0.0"
                                        },
                                        "packageContent": "{{baseUrl}}/download/some.package/2.0.0/some.package.2.0.0.nupkg",
                                    }
                                ]
                            }
                        ]
                    }
                    """)),
                "/download/delisted.package/5.0.0/delisted.package.5.0.0.nupkg" =>
                    (200, MockNuGetPackage.CreateSimplePackage("Delisted.Package", "5.0.0", "net45").GetZipStream().ReadAllBytes()),
                "/download/some.package/1.0.0/some.package.1.0.0.nupkg" =>
                    (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net45").GetZipStream().ReadAllBytes()),
                "/download/some.package/2.0.0/some.package.2.0.0.nupkg" =>
                    (200, MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net45").GetZipStream().ReadAllBytes()),
                _ => (404, Encoding.UTF8.GetBytes("{}")), // everything is missing
            };
        }
        using var cache = new TemporaryDirectory();
        using var http = TestHttpServer.CreateTestServer(TestHttpHandler);
        await TestAsync("Some.Package", "1.0.0", "2.0.0",
            projectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.6.2</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Delisted.Package">
                      <HintPath>packages\Delisted.Package.5.0.0\lib\net45\Delisted.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Some.Package">
                      <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            packagesConfigContents: """
                <packages>
                  <package id="Delisted.Package" version="5.0.0" targetFramework="net462" />
                  <package id="Some.Package" version="1.0.0" targetFramework="net462" />
                </packages>
                """,
            additionalFiles:
            [
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """)
            ],
            expectedProjectContents: """
                <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                  <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                  <PropertyGroup>
                    <TargetFrameworkVersion>v4.6.2</TargetFrameworkVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <None Include="packages.config" />
                  </ItemGroup>
                  <ItemGroup>
                    <Reference Include="Delisted.Package">
                      <HintPath>packages\Delisted.Package.5.0.0\lib\net45\Delisted.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Some.Package">
                      <HintPath>packages\Some.Package.2.0.0\lib\net45\Some.Package.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
            expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="Delisted.Package" version="5.0.0" targetFramework="net462" />
                  <package id="Some.Package" version="2.0.0" targetFramework="net462" />
                </packages>
                """,
            expectedUpdateOperations: [
                new DirectUpdate() { DependencyName = "Some.Package", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/project.csproj", "/packages.config"] }
            ]
        );
    }

    [Fact]
    public async Task MissingTargetsAreReported()
    {
        // arrange
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <Import Project="this.file.does.not.exist.targets" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("packages.config", """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("NuGet.Config", """
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="packages" />
                      </packageSources>
                    </configuration>
                    """)
            ]
        );
        var packages = new[] {
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net45"),
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net45"),
        };
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, temporaryDirectory.DirectoryPath);

        // act
        var fileNotFoundException = await Assert.ThrowsAsync<MissingFileException>(() => PackagesConfigUpdater.UpdateDependencyAsync(
            temporaryDirectory.DirectoryPath,
            Path.Join(temporaryDirectory.DirectoryPath, "project.csproj"),
            "Some.Package",
            "1.0.0",
            "1.1.0",
            Path.Join(temporaryDirectory.DirectoryPath, "packages.config"),
            new TestLogger()
        ));

        // assert
        var error = JobErrorBase.ErrorFromException(fileNotFoundException, "TEST-JOB-ID", temporaryDirectory.DirectoryPath);
        var fileNotFound = Assert.IsType<DependencyFileNotFound>(error);
        var filePath = Assert.IsType<string>(fileNotFound.Details["file-path"]);
        Assert.Equal(Path.Combine(temporaryDirectory.DirectoryPath, "this.file.does.not.exist.targets").NormalizePathToUnix(), filePath);
    }

    [Fact]
    public async Task MissingVisualStudioComponentTargetsAreReportedAsMissingFiles()
    {
        // arrange
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <Import Project="$(MSBuildExtensionsPath32)\Microsoft\VisualStudio\v$(VisualStudioVersion)\Some.Visual.Studio.Component.props" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("packages.config", """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("NuGet.Config", """
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="packages" />
                      </packageSources>
                    </configuration>
                    """)
            ]
        );
        var packages = new[]
        {
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net45"),
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net45"),
        };
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, temporaryDirectory.DirectoryPath);

        // act
        var fileNotFoundException = await Assert.ThrowsAsync<MissingFileException>(() => PackagesConfigUpdater.UpdateDependencyAsync(
            temporaryDirectory.DirectoryPath,
            Path.Join(temporaryDirectory.DirectoryPath, "project.csproj"),
            "Some.Package",
            "1.0.0",
            "1.1.0",
            Path.Join(temporaryDirectory.DirectoryPath, "packages.config"),
            new TestLogger()
        ));

        // assert
        var error = JobErrorBase.ErrorFromException(fileNotFoundException, "TEST-JOB-ID", temporaryDirectory.DirectoryPath);
        var fileNotFound = Assert.IsType<DependencyFileNotFound>(error);
        var filePath = Assert.IsType<string>(fileNotFound.Details["file-path"]);
        Assert.Equal("$(MSBuildExtensionsPath32)/Microsoft/VisualStudio/v$(VisualStudioVersion)/Some.Visual.Studio.Component.props", filePath);
    }

    [Theory]
    [InlineData(401)]
    [InlineData(403)]
    public async Task ReportsPrivateSourceAuthenticationFailure(int httpStatusCode)
    {
        // arrange
        (int, string) TestHttpHandler(string uriString)
        {
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                _ => (httpStatusCode, "{}"), // everything is unauthorized
            };
        }
        using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("packages.config", """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """)
            ]
        );
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory([], Path.Combine(temporaryDirectory.DirectoryPath, "packages"));

        // act
        var requestException = await Assert.ThrowsAsync<HttpRequestException>(() => PackagesConfigUpdater.UpdateDependencyAsync(
            temporaryDirectory.DirectoryPath,
            Path.Join(temporaryDirectory.DirectoryPath, "project.csproj"),
            "Some.Package",
            "1.0.0",
            "1.1.0",
            Path.Join(temporaryDirectory.DirectoryPath, "packages.config"),
            new TestLogger()
        ));

        // assert
        var error = JobErrorBase.ErrorFromException(requestException, "TEST-JOB-ID", temporaryDirectory.DirectoryPath);
        var privateSourceAuthError = Assert.IsType<PrivateSourceAuthenticationFailure>(error);
        var urls = Assert.IsType<string>(privateSourceAuthError.Details["source"]);
        Assert.Equal($"({http.BaseUrl.TrimEnd('/')}/index.json)", urls);
    }

    [Fact]
    public async Task ReportsUnexpectedResponseFromNuGetServer()
    {
        // arrange
        static (int, string) TestHttpHandler(string uriString)
        {
            var uri = new Uri(uriString, UriKind.Absolute);
            var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
            return uri.PathAndQuery switch
            {
                // initial and search query are good, update should be possible...
                "/index.json" => (200, $$"""
                    {
                        "version": "3.0.0",
                        "resources": [
                            {
                                "@id": "{{baseUrl}}/download",
                                "@type": "PackageBaseAddress/3.0.0"
                            },
                            {
                                "@id": "{{baseUrl}}/query",
                                "@type": "SearchQueryService"
                            },
                            {
                                "@id": "{{baseUrl}}/registrations",
                                "@type": "RegistrationsBaseUrl"
                            }
                        ]
                    }
                    """),
                "/registrations/some.package/index.json" => (200, $$"""
                        {
                            "count": 1,
                            "items": [
                                {
                                    "lower": "1.0.0",
                                    "upper": "1.1.0",
                                    "items": [
                                        {
                                            "catalogEntry": {
                                                "id": "Some.Package",
                                                "listed": true,
                                                "version": "1.0.0"
                                            },
                                            "packageContent": "{{baseUrl}}/download/some.package/1.0.0/some.package.1.0.0.nupkg",
                                        },
                                        {
                                            "catalogEntry": {
                                                "id": "Some.Package",
                                                "listed": true,
                                                "version": "1.1.0"
                                            },
                                            "packageContent": "{{baseUrl}}/download/some.package/1.1.0/some.package.1.1.0.nupkg",
                                        }
                                    ]
                                }
                            ]
                        }
                        """),
                // ...but all other calls to the server fail
                _ => (500, "{}"),
            };
        }
        using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("packages.config", """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """),
                ("NuGet.Config", $"""
                    <configuration>
                      <packageSources>
                        <clear />
                        <add key="private_feed" value="{http.BaseUrl.TrimEnd('/')}/index.json" allowInsecureConnections="true" />
                      </packageSources>
                    </configuration>
                    """)
            ]
        );
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory([], Path.Combine(temporaryDirectory.DirectoryPath, "packages"));

        // act
        var requestException = await Assert.ThrowsAsync<HttpRequestException>(() => PackagesConfigUpdater.UpdateDependencyAsync(
            temporaryDirectory.DirectoryPath,
            Path.Join(temporaryDirectory.DirectoryPath, "project.csproj"),
            "Some.Package",
            "1.0.0",
            "1.1.0",
            Path.Join(temporaryDirectory.DirectoryPath, "packages.config"),
            new TestLogger()
        ));

        // assert
        var error = JobErrorBase.ErrorFromException(requestException, "TEST-JOB-ID", temporaryDirectory.DirectoryPath);
        var badResponse = Assert.IsType<PrivateSourceBadResponse>(error);
        var urls = Assert.IsType<string>(badResponse.Details["source"]);
        Assert.Equal($"({http.BaseUrl.TrimEnd('/')}/index.json)", urls);
    }

    [Fact]
    public async Task MissingDependencyErrorIsReported()
    {
        // trying to update Some.Package from 1.0.1 to 1.0.2, but another package isn't available; update fails
        // arrange
        using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.5</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.1\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                        <Reference Include="Unrelated.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Unrelated.Package.1.0.0\lib\net45\Unrelated.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """),
                ("packages.config", """
                    <packages>
                      <package id="Some.Package" version="1.0.1" targetFramework="net45" />
                      <package id="Unrelated.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """)
            ]
        );
        var packages = new[]
        {
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net45"),
            MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.2", "net45"),
            // the package `Unrelated.Package/1.0.0` is missing and will cause the update to fail
        };
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, temporaryDirectory.DirectoryPath);

        // act
        var notFoundException = await Assert.ThrowsAsync<DependencyNotFoundException>(() => PackagesConfigUpdater.UpdateDependencyAsync(
            temporaryDirectory.DirectoryPath,
            Path.Join(temporaryDirectory.DirectoryPath, "project.csproj"),
            "Some.Package",
            "1.0.1",
            "1.0.2",
            Path.Join(temporaryDirectory.DirectoryPath, "packages.config"),
            new TestLogger()
        ));

        // assert
        var error = JobErrorBase.ErrorFromException(notFoundException, "TEST-JOB-ID", temporaryDirectory.DirectoryPath);
        var notFound = Assert.IsType<DependencyNotFound>(error);
        var depName = Assert.IsType<string>(notFound.Details["source"]);
        Assert.Equal("Unrelated.Package", depName);
    }

    [Theory]
    [MemberData(nameof(PackagesDirectoryPathTestData))]
    public async Task PathToPackagesDirectoryCanBeDetermined(string projectContents, string? packagesConfigContents, string dependencyName, string dependencyVersion, string expectedPackagesDirectoryPath)
    {
        using var tempDir = new TemporaryDirectory();
        string? packagesConfigPath = null;
        if (packagesConfigContents is not null)
        {
            packagesConfigPath = Path.Join(tempDir.DirectoryPath, "packages.config");
            await File.WriteAllTextAsync(packagesConfigPath, packagesConfigContents, TestContext.Current.CancellationToken);
        }

        var projectBuildFile = ProjectBuildFile.Parse("/", "project.csproj", projectContents);
        var actualPackagesDirectorypath = PackagesConfigUpdater.GetPathToPackagesDirectory(projectBuildFile, dependencyName, dependencyVersion, packagesConfigPath);
        Assert.Equal(expectedPackagesDirectoryPath, actualPackagesDirectorypath);
    }

    public static IEnumerable<object?[]> PackagesDirectoryPathTestData()
    {
        // project with namespace
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../packages"
        ];

        // project without namespace
        yield return
        [
            // project contents
            """
            <Project>
              <ItemGroup>
                <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../packages"
        ];

        // project with non-standard packages path
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\not-a-path-you-would-expect\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../not-a-path-you-would-expect"
        ];

        // project without expected packages path, but has others
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Some.Other.Package, Version=1.2.3.4, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\..\..\still-a-usable-path\Some.Other.Package.1.2.3\lib\net45\Some.Other.Package.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
              <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
            </packages>
            """,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../../../still-a-usable-path"
        ];

        // project without expected package, but exists in packages.config, default is returned
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
              <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net45" />
            </packages>
            """,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "../packages"
        ];

        // project without expected package and not in packages.config
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
            </packages>
            """,
            // dependency name
            "Newtonsoft.Json",
            // dependency version
            "7.0.1",
            // expected packages directory path
            null
        ];

        // project with differing package name and assembly name
        yield return
        [
            // project contents
            """
            <Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Assembly.For.Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                  <HintPath>..\packages\Some.Package.1.0.0\lib\net45\Assembly.For.Some.Package.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            null,
            // dependency name
            "Some.Package",
            // dependency version
            "1.0.0",
            // expected packages directory path
            "../packages"
        ];

        // package has no assembly version
        yield return
        [
            // project contents
            """
            <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
              <ItemGroup>
                <Reference Include="Some.Package">
                  <HintPath>packages\Some.Package.7.0.1\lib\net45\Some.Package.dll</HintPath>
                  <Private>True</Private>
                </Reference>
              </ItemGroup>
            </Project>
            """,
            // packages.config contents
            """
            <packages>
              <package id="Some.Package" version="7.0.1" targetFramework="net45" />
            </packages>
            """,
            // dependency name
            "Some.Package",
            // dependency version
            "7.0.1",
            // expected packages directory path
            "packages"
        ];
    }

    private static async Task TestAsync(
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        string projectContents,
        string packagesConfigContents,
        string expectedProjectContents,
        string expectedPackagesConfigContents,
        ImmutableArray<UpdateOperationBase> expectedUpdateOperations,
        (string Path, string Content)[]? additionalFiles = null,
        (string Path, string Content)[]? additionalFilesExpected = null,
        string projectPath = "project.csproj",
        string packagesConfigPath = "packages.config",
        MockNuGetPackage[]? packages = null
    )
    {
        // arrange
        var allFiles = new List<(string Path, string Content)>
        {
            (projectPath, projectContents),
            (packagesConfigPath, packagesConfigContents)
        };
        allFiles.AddRange(additionalFiles ?? []);
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync([.. allFiles]);
        await UpdateWorkerTestBase.MockNuGetPackagesInDirectory(packages, tempDir.DirectoryPath);
        var logger = new TestLogger();

        // act
        var updateOperations = await PackagesConfigUpdater.UpdateDependencyAsync(
            tempDir.DirectoryPath,
            Path.Join(tempDir.DirectoryPath, projectPath),
            dependencyName,
            previousDependencyVersion,
            newDependencyVersion,
            Path.Join(tempDir.DirectoryPath, packagesConfigPath),
            logger
        );

        // assert
        var expectedFilePaths = new[] { projectPath, packagesConfigPath }
            .Concat(additionalFilesExpected?.Select(f => f.Path) ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var actualFiles = await tempDir.ReadFileContentsAsync(expectedFilePaths);
        foreach (var expectedFilePath in expectedFilePaths)
        {
            var expectedFileContent = await File.ReadAllTextAsync(Path.Join(tempDir.DirectoryPath, expectedFilePath));
            var actualFile = actualFiles.FirstOrDefault(f => f.Path.Equals(expectedFilePath, StringComparison.OrdinalIgnoreCase));
            if (actualFile != default)
            {
                Assert.Equal(expectedFileContent.Replace("\r", ""), actualFile.Contents.Replace("\r", ""));
            }
            else
            {
                Assert.Fail($"Unexpected file found: {actualFile.Path}");
            }
        }

        var actualUpdateOperationsJson = updateOperations
            .Select(u => u with { UpdatedFiles = [.. u.UpdatedFiles.Select(f => Path.GetRelativePath(tempDir.DirectoryPath, f).FullyNormalizedRootedPath())] })
            .Select(u => JsonSerializer.Serialize(u, RunWorker.SerializerOptions))
            .ToImmutableArray();
        var expectedUpdateOperationsJson = expectedUpdateOperations.Select(u => JsonSerializer.Serialize(u, RunWorker.SerializerOptions)).ToImmutableArray();
        AssertEx.Equal(expectedUpdateOperationsJson, actualUpdateOperationsJson);
    }
}
