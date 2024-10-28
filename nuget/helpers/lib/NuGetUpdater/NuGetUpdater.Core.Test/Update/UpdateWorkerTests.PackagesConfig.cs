using System.Collections.Immutable;
using System.Text;
using System.Text.Json;

using NuGet;

using NuGetUpdater.Core.Test.Updater;
using NuGetUpdater.Core.Updater;

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
        public async Task UpdatePackageWithTargetsFileWhereProjectUsesBackslashes()
        {
            // The bug that caused this test to be written did not repro on Windows.  The reason is that the packages
            // directory is determined to be `..\packages`, but the backslash was retained.  Later when packages were
            // restored to that location, a directory with a name like `..?packages` would be created which didn't
            // match the <Import> element's path of "..\packages\..." that had no `Condition="Exists(path)"` attribute.
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net45"),
                    new MockNuGetPackage("Package.With.Targets", "1.0.0", Files: [("build/SomeFile.targets", Encoding.UTF8.GetBytes("<Project />"))]),
                ],
                // existing
                projectFile: ("src/project.csproj", """
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
                    """),
                additionalFiles:
                [
                    ("src/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Package.With.Targets" version="1.0.0" targetFramework="net45" />
                          <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                        </packages>
                        """)
                ],
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
                          <HintPath>..\packages\Some.Package.2.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="..\packages\Package.With.Targets.1.0.0\build\SomeFile.targets" />
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("src/packages.config", """
                        <?xml version="1.0" encoding="utf-8"?>
                        <packages>
                          <package id="Package.With.Targets" version="1.0.0" targetFramework="net45" />
                          <package id="Some.Package" version="2.0.0" targetFramework="net45" />
                        </packages>
                        """)
                ]
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

        // the xml can take various shapes and they're all formatted, so we need very specific values here
        [Theory]
        [InlineData("<Content Include=\"web.config\" />")]
        [InlineData("<Content Include=\"web.config\">\n    </Content>")]
        [InlineData("<Content Include=\"web.config\">\n      <SubType>Designer</SubType>\n    </Content>")]
        public async Task UpdateBindingRedirectInWebConfig(string webConfigXml)
        {
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
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
        public async Task UpdateBindingRedirect_UnrelatedAssemblyReferenceWithMissingPublicKeyTokenAttribute()
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
                        <Reference Include="Some.Unrelated.Package, Version=1.0.0.0, Culture=neutral">
                          <HintPath>packages\Some.Unrelated.Package.1.0.0\lib\net45\Some.Unrelated.Package.dll</HintPath>
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
                              <dependentAssembly>
                                <assemblyIdentity name="Some.Unrelated.Package" culture="neutral" />
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
                        <Reference Include="Some.Unrelated.Package, Version=1.0.0.0, Culture=neutral">
                          <HintPath>packages\Some.Unrelated.Package.1.0.0\lib\net45\Some.Unrelated.Package.dll</HintPath>
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
                              <dependentAssembly>
                                <assemblyIdentity name="Some.Unrelated.Package" culture="neutral" />
                                <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
                              </dependentAssembly>
                            </assemblyBinding>
                          </runtime>
                        </configuration>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateBindingRedirect_UnrelatedAssemblyReferenceWithMissingCultureAttribute()
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
                        <Reference Include="Some.Unrelated.Package, Version=1.0.0.0, PublicKeyToken=null">
                          <HintPath>packages\Some.Unrelated.Package.1.0.0\lib\net45\Some.Unrelated.Package.dll</HintPath>
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
                              <dependentAssembly>
                                <assemblyIdentity name="Some.Unrelated.Package" publicKeyToken="null" />
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
                        <Reference Include="Some.Unrelated.Package, Version=1.0.0.0, PublicKeyToken=null">
                          <HintPath>packages\Some.Unrelated.Package.1.0.0\lib\net45\Some.Unrelated.Package.dll</HintPath>
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
                              <dependentAssembly>
                                <assemblyIdentity name="Some.Unrelated.Package" publicKeyToken="null" />
                                <bindingRedirect oldVersion="0.0.0.0-1.0.0.0" newVersion="1.0.0.0" />
                              </dependentAssembly>
                            </assemblyBinding>
                          </runtime>
                        </configuration>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateBindingRedirect_DuplicateRedirectsForTheSameAssemblyAreRemoved()
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
        public async Task UpdateBindingRedirect_ExistingRedirectForAssemblyPublicKeyTokenDiffersByCase()
        {
            // Generated using "sn -k keypair.snk && sn -p keypair.snk public.snk" then converting public.snk to base64
            // https://learn.microsoft.com/en-us/dotnet/standard/assembly/create-public-private-key-pair
            var assemblyStrongNamePublicKey = Convert.FromBase64String(
              "ACQAAASAAACUAAAABgIAAAAkAABSU0ExAAQAAAEAAQAJJW4hmKpxa9pU0JPDvJ9KqjvfQuMUovGtFjkZ9b0i1KQ/7kqEOjW3Va0eGpU7Kz0qHp14iYQ3SsMzBZU3mZ2Ezeqg+dCVuDk7o2lp++4m1FstHsebtXBetyOzWkneo+3iKSzOQ7bOXj2s5M9umqRPk+yj0ZBILf+HvfAd07iIuQ=="
            ).ToImmutableArray();

            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
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
                additionalFiles:
                [
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
                additionalFilesExpected:
                [
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
                ]
            );
        }

        [Fact]
        public async Task UpdateBindingRedirect_ConfigXmlDeclarationNodeIsPreserved()
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
                        <?xml version="1.0" encoding="utf-8"?>
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
            using var env = new TemporaryEnvironment([
                ("NUGET_PACKAGES", Path.Join(cache.DirectoryPath, "NUGET_PACKAGES")),
                ("NUGET_HTTP_CACHE_PATH", Path.Join(cache.DirectoryPath, "NUGET_HTTP_CACHE_PATH")),
                ("NUGET_SCRATCH", Path.Join(cache.DirectoryPath, "NUGET_SCRATCH")),
                ("NUGET_PLUGINS_CACHE_PATH", Path.Join(cache.DirectoryPath, "NUGET_PLUGINS_CACHE_PATH")),
            ]);
            using var http = TestHttpServer.CreateTestServer(TestHttpHandler);
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
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
                    """
            );
        }

        [Fact]
        public async Task MissingTargetsAreReported()
        {
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
            MockNuGetPackage[] packages =
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net45"),
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net45"),
            ];
            await MockNuGetPackagesInDirectory(packages, Path.Combine(temporaryDirectory.DirectoryPath, "packages"));
            var resultOutputPath = Path.Combine(temporaryDirectory.DirectoryPath, "result.json");

            var worker = new UpdaterWorker(new TestLogger());
            await worker.RunAsync(temporaryDirectory.DirectoryPath, "project.csproj", "Some.Package", "1.0.0", "1.1.0", isTransitive: false, resultOutputPath: resultOutputPath);

            var resultContents = await File.ReadAllTextAsync(resultOutputPath);
            var result = JsonSerializer.Deserialize<UpdateOperationResult>(resultContents, UpdaterWorker.SerializerOptions)!;
            Assert.Equal(ErrorType.MissingFile, result.ErrorType);
            Assert.Equal(Path.Combine(temporaryDirectory.DirectoryPath, "this.file.does.not.exist.targets"), result.ErrorDetails.ToString());
        }

        [Fact]
        public async Task ReportsPrivateSourceAuthenticationFailure()
        {
            static (int, string) TestHttpHandler(string uriString)
            {
                var uri = new Uri(uriString, UriKind.Absolute);
                var baseUrl = $"{uri.Scheme}://{uri.Host}:{uri.Port}";
                return uri.PathAndQuery switch
                {
                    _ => (401, "{}"), // everything is unauthorized
                };
            }
            using var http = TestHttpServer.CreateTestStringServer(TestHttpHandler);
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
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
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                packagesConfigContents: """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
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
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                expectedPackagesConfigContents: """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """,
                expectedResult: new()
                {
                    ErrorType = ErrorType.AuthenticationFailure,
                    ErrorDetails = $"({http.BaseUrl.TrimEnd('/')}/index.json)",
                }
            );
        }

        [Fact]
        public async Task ReportsUnexpectedResponseFromNuGetServer()
        {
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
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
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
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                packagesConfigContents: """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
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
                        <Reference Include="Some.Package, Version=1.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed">
                          <HintPath>packages\Some.Package.1.0.0\lib\net45\Some.Package.dll</HintPath>
                          <Private>True</Private>
                        </Reference>
                      </ItemGroup>
                      <Import Project="$(MSBuildToolsPath)\Microsoft.CSharp.targets" />
                    </Project>
                    """,
                expectedPackagesConfigContents: """
                    <packages>
                      <package id="Some.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """,
                expectedResult: new()
                {
                    ErrorType = ErrorType.Unknown,
                    ErrorDetailsRegex = "Response status code does not indicate success",
                }
            );
        }

        [Fact]
        public async Task MissingDependencyErrorIsReported()
        {
            // trying to update Some.Package from 1.0.1 to 1.0.2, but another package isn't available; update fails
            await TestUpdateForProject("Some.Package", "1.0.1", "1.0.2",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.1", "net45"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.2", "net45"),

                    // the package `Unrelated.Package/1.0.0` is missing and will cause the update to fail
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
                    """,
                packagesConfigContents: """
                    <packages>
                      <package id="Some.Package" version="1.0.1" targetFramework="net45" />
                      <package id="Unrelated.Package" version="1.0.0" targetFramework="net45" />
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
                    """,
                expectedPackagesConfigContents: """
                    <packages>
                      <package id="Some.Package" version="1.0.1" targetFramework="net45" />
                      <package id="Unrelated.Package" version="1.0.0" targetFramework="net45" />
                    </packages>
                    """,
                expectedResult: new()
                {
                    ErrorType = ErrorType.UpdateNotPossible,
                    ErrorDetails = new[] { "Unrelated.Package.1.0.0" },
                }
            );
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
            MockNuGetPackage[]? packages = null,
            ExpectedUpdateOperationResult? expectedResult = null)
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
                packages: packages,
                expectedResult: expectedResult);
        }
    }
}
