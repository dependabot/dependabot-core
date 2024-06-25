using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class PackagesConfig : UpdateWorkerTestBase
    {
        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfig()
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
                // expected
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
                    """
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfig_ReferenceHasNoAssemblyVersion()
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
                // expected
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
                    """
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfig_SpecifiedDependencyHasNoPackagesPath()
        {
            // update Package.With.No.Assembly from 1.0.0
            await TestUpdateForProject("Package.With.No.Assembly", "1.0.0", "1.1.0",
                packages:
                [
                    // this package has no `lib` directory, but it's still valid because it has a `content` directory
                    new MockNuGetPackage("Package.With.No.Assembly", "1.0.0", Files: [("content/some-content.txt", [])]),
                    new MockNuGetPackage("Package.With.No.Assembly", "1.1.0", Files: [("content/some-content.txt", [])]),
                    // this is a regular package that's not being updated
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net46"),
                ],
                // existing
                projectContents: """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.6</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package">
                          <HintPath>packages\Some.Package.1.0.0\lib\net46\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                packagesConfigContents: """
                    <packages>
                      <package id="Package.With.No.Assembly" version="1.0.0" targetFramework="net46" />
                      <package id="Some.Package" version="1.0.0" targetFramework="net46" />
                    </packages>
                    """,
                // expected
                expectedProjectContents: """
                    <Project ToolsVersion="15.0" DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <Import Project="$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props" Condition="Exists('$(MSBuildExtensionsPath)\$(MSBuildToolsVersion)\Microsoft.Common.props')" />
                      <PropertyGroup>
                        <TargetFrameworkVersion>v4.6</TargetFrameworkVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <None Include="packages.config" />
                      </ItemGroup>
                      <ItemGroup>
                        <Reference Include="Some.Package">
                          <HintPath>packages\Some.Package.1.0.0\lib\net46\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                expectedPackagesConfigContents: """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Package.With.No.Assembly" version="1.1.0" targetFramework="net46" />
                      <package id="Some.Package" version="1.0.0" targetFramework="net46" />
                    </packages>
                    """
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfig_NoPackagesPathCanBeFound()
        {
            // update Package.With.No.Assembly from 1.0.0 to 1.0.0
            await TestUpdateForProject("Package.With.No.Assembly", "1.0.0", "1.1.0",
                packages:
                [
                    // this package has no `lib` directory, but it's still valid because it has a `content` directory
                    new MockNuGetPackage("Package.With.No.Assembly", "1.0.0", Files: [("content/some-content.txt", [])]),
                    new MockNuGetPackage("Package.With.No.Assembly", "1.1.0", Files: [("content/some-content.txt", [])]),
                ],
                // existing
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
                // expected
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
                    """
            );
        }

        [Fact]
        public async Task UpdateDependency_NoAssembliesAndContentDirectoryDiffersByCase()
        {
            // update Package.With.No.Assembly from 1.0.0 to 1.0.0
            await TestUpdateForProject("Package.With.No.Assembly", "1.0.0", "1.1.0",
                packages:
                [
                    // this package is expected to have a directory named `content`, but here it differs by case as `Content`
                    new MockNuGetPackage("Package.With.No.Assembly", "1.0.0", Files: [("Content/some-content.txt", [])]),
                    new MockNuGetPackage("Package.With.No.Assembly", "1.1.0", Files: [("Content/some-content.txt", [])]),
                ],
                // existing
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
                // expected
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
                    """
            );
        }

        [Fact]
        public async Task UpdateSingleDependencyInPackagesConfigButNotToLatest()
        {
            // update Some.Package from 7.0.1 to 9.0.1, purposefully not updating all the way to the newest
            await TestUpdateForProject("Some.Package", "7.0.1", "9.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
                ],
                // existing
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
                // expected
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
                          <HintPath>packages\Some.Package.9.0.1\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                expectedPackagesConfigContents: """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Package" version="9.0.1" targetFramework="net45" />
                    </packages>
                    """
            );
        }

        [Fact]
        public async Task UpdateSpecifiedVersionInPackagesConfigButNotOthers()
        {
            // update Some.Package from 7.0.1 to 13.0.1, but leave Some.Unrelated.Package alone
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    // this package is upgraded
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net45"),
                    // this package is not upgraded
                    MockNuGetPackage.CreateSimplePackage("Some.Unrelated.Package", "1.0.0", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Unrelated.Package", "1.1.0", "net45"),
                ],
                // existing
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
                        <Reference Include="Some.Unrelated.Package">
                          <HintPath>packages\Some.Unrelated.Package.1.0.0\lib\net45\Some.Unrelated.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                packagesConfigContents: """
                    <packages>
                      <package id="Some.Unrelated.Package" version="1.0.0" targetFramework="net45" />
                      <package id="Some.Package" version="7.0.1" targetFramework="net45" />
                    </packages>
                    """,
                // expected
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
                        <Reference Include="Some.Unrelated.Package">
                          <HintPath>packages\Some.Unrelated.Package.1.0.0\lib\net45\Some.Unrelated.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                expectedPackagesConfigContents: """
                    <?xml version="1.0" encoding="utf-8"?>
                    <packages>
                      <package id="Some.Unrelated.Package" version="1.0.0" targetFramework="net45" />
                      <package id="Some.Package" version="13.0.1" targetFramework="net45" />
                    </packages>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackagesConfigWithNonStandardLocationOfPackagesDirectory()
        {
            // update Some.Package from 7.0.1 to 13.0.1 with the actual assembly in a non-standard location
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
                // expected
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
                    """
            );
        }

        [Fact]
        public async Task UpdateBindingRedirectInAppConfig()
        {
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
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
                additionalFiles:
                [
                    ("app.config", """
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
                additionalFilesExpected:
                [
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
                ]
            );
        }

        [Fact]
        public async Task UpdateBindingRedirectInWebConfig()
        {
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0"),
                    MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0"),
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
                        <Content Include="web.config" />
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
                        <Content Include="web.config" />
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
                additionalFilesExpected:
                [
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
                ]
            );
        }

        [Fact]
        public async Task AddsBindingRedirectInWebConfig()
        {
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "7.0.1", "net45", "7.0.0.0"),
                    MockNuGetPackage.CreatePackageWithAssembly("Some.Package", "13.0.1", "net45", "13.0.0.0"),
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
                        <Content Include="web.config" />
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
                          </runtime>
                        </configuration>
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
                        <Content Include="web.config" />
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
                additionalFilesExpected:
                [
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
                ]
            );
        }

        [Fact]
        public async Task PackagesConfigUpdateCanHappenEvenWithMismatchedVersionNumbers()
        {
            // `packages.config` reports `7.0.1` and that's what we want to update, but the project file has a mismatch that's corrected
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
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
                    """
            );
        }

        [Fact]
        public async Task PackagesConfigUpdateIsNotThwartedBy_VSToolsPath_PropertyBeingSetInUserCode()
        {
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
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
                      <PropertyGroup>
                        <!-- some project files set this property which makes the Microsoft.WebApplication.targets import a few lines down always fail -->
                        <VSToolsPath Condition="'$(VSToolsPath)' == ''">C:\some\path\that\does\not\exist</VSToolsPath>
                      </PropertyGroup>
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
                      <PropertyGroup>
                        <!-- some project files set this property which makes the Microsoft.WebApplication.targets import a few lines down always fail -->
                        <VSToolsPath Condition="'$(VSToolsPath)' == ''">C:\some\path\that\does\not\exist</VSToolsPath>
                      </PropertyGroup>
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
                    """
            );
        }

        [Fact]
        public async Task PackageCanBeUpdatedWhenAnotherInstalledPackageHasBeenDelisted()
        {
            // updating one package (Newtonsoft.Json) when another installed package (FSharp.Core/5.0.3-beta.21369.4) has been delisted
            await TestUpdateForProject("Newtonsoft.Json", "7.0.1", "13.0.1",
                // existing
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
                    <Reference Include="FSharp.Core, Version=5.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a">
                      <HintPath>packages\FSharp.Core.5.0.3-beta.21369.4\lib\netstandard2.0\FSharp.Core.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Newtonsoft.Json, Version=7.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Newtonsoft.Json.7.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                packagesConfigContents: """
                <packages>
                  <package id="FSharp.Core" version="5.0.3-beta.21369.4" targetFramework="net462" />
                  <package id="Newtonsoft.Json" version="7.0.1" targetFramework="net462" />
                </packages>
                """,
                // expected
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
                    <Reference Include="FSharp.Core, Version=5.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a">
                      <HintPath>packages\FSharp.Core.5.0.3-beta.21369.4\lib\netstandard2.0\FSharp.Core.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                    <Reference Include="Newtonsoft.Json, Version=13.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                      <HintPath>packages\Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll</HintPath>
                      <Private>True</Private>
                    </Reference>
                  </ItemGroup>
                  <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                </Project>
                """,
                expectedPackagesConfigContents: """
                <?xml version="1.0" encoding="utf-8"?>
                <packages>
                  <package id="FSharp.Core" version="5.0.3-beta.21369.4" targetFramework="net462" />
                  <package id="Newtonsoft.Json" version="13.0.1" targetFramework="net462" />
                </packages>
                """);
        }

        protected static Task TestUpdateForProject(
            string dependencyName,
            string oldVersion,
            string newVersion,
            string projectContents,
            string packagesConfigContents,
            string expectedProjectContents,
            string expectedPackagesConfigContents,
            (string Path, string Content)[]? additionalFiles = null,
            (string Path, string Content)[]? additionalFilesExpected = null,
            MockNuGetPackage[]? packages = null)
        {
            var realizedAdditionalFiles = new List<(string Path, string Content)>
            {
                ("packages.config", packagesConfigContents),
            };
            if (additionalFiles is not null)
            {
                realizedAdditionalFiles.AddRange(additionalFiles);
            }

            var realizedAdditionalFilesExpected = new List<(string Path, string Content)>
            {
                ("packages.config", expectedPackagesConfigContents),
            };
            if (additionalFilesExpected is not null)
            {
                realizedAdditionalFilesExpected.AddRange(additionalFilesExpected);
            }

            return TestUpdateForProject(
                dependencyName,
                oldVersion,
                newVersion,
                projectContents,
                expectedProjectContents,
                additionalFiles: realizedAdditionalFiles.ToArray(),
                additionalFilesExpected: realizedAdditionalFilesExpected.ToArray(),
                packages: packages);
        }
    }
}
