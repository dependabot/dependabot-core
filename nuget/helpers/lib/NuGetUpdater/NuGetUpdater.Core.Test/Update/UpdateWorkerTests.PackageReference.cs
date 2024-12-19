using System.Linq;
using System.Text;
using System.Text.Json;

using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public partial class UpdateWorkerTests
{
    public class PackageReference : UpdateWorkerTestBase
    {
        [Theory]
        [InlineData("net472")]
        [InlineData("net7.0")]
        [InlineData("net8.0")]
        [InlineData("net9.0")]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceInclude(string tfm)
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", tfm),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", tfm),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>{tfm}</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>{tfm}</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task UpdateVersionChildElement_InProjectFile_ForPackageReferenceIncludeTheory(bool useLegacyDependencySolver)
        {
            // update Some.Package from 9.0.1 to 13.0.1
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package">
                          <Version>9.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package">
                          <Version>13.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """
              );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task PeerDependenciesAreUpdatedEvenWhenNotExplicit(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Transitive.Package", "[1.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0", [(null, [("Transitive.Package", "[2.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Package", "2.0.0", "net8.0"),
                ],
                projectFile: ("a/a.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """),
                additionalFiles:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Transitive.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="2.0.0" />
                            <PackageVersion Include="Transitive.Package" Version="2.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task PackageIsUpdatedFromCommonTargetsFile(bool useDirectDiscovery)
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "2.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0"),
                ],
                experimentsManager: new ExperimentsManager() { UseDirectDiscovery = useDirectDiscovery },
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <Import Project="CommonPackages.targets" />
                    </Project>
                    """,
                additionalFiles:
                [
                    ("CommonPackages.targets", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="Some.Package">
                              <Version>1.0.0</Version>
                            </PackageReference>
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <Import Project="CommonPackages.targets" />
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("CommonPackages.targets", """
                        <Project>
                          <ItemGroup>
                            <PackageReference Include="Some.Package">
                              <Version>2.0.0</Version>
                            </PackageReference>
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task CallingResolveDependencyConflictsNew()
        {
            // update Microsoft.CodeAnalysis.Common from 4.9.2 to 4.10.0
            await TestUpdateForProject("Microsoft.CodeAnalysis.Common", "4.9.2", "4.10.0",
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                        </PropertyGroup>
                        <ItemGroup>
                            <PackageReference Include="Microsoft.CodeAnalysis.Compilers" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.9.2" />
                            <PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="4.9.2" />
                        </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                        </PropertyGroup>
                        <ItemGroup>
                            <PackageReference Include="Microsoft.CodeAnalysis.Compilers" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.Common" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" Version="4.10.0" />
                            <PackageReference Include="Microsoft.CodeAnalysis.VisualBasic" Version="4.10.0" />
                        </ItemGroup>
                    </Project>
                    """
              );
        }

        [Fact]
        public async Task UpdateVersions_InProjectFile_ForDuplicatePackageReferenceInclude()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                        <PackageReference Include="Some.Package">
                            <Version>9.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                        <PackageReference Include="Some.Package">
                            <Version>13.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task PartialUpdate_InMultipleProjectFiles_ForVersionConstraint()
        {
            // update Some.Package from 12.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="12.0.1" />
                        <ProjectReference Include="../Project/Project.csproj" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    (Path: "src/Project/Project.csproj", Content: """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="[12.0.1, 13.0.0)" />
                          </ItemGroup>
                        </Project>
                        """),
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                        <ProjectReference Include="../Project/Project.csproj" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    (Path: "src/Project/Project.csproj", Content: """
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="[12.0.1, 13.0.0)" />
                          </ItemGroup>
                        </Project>
                        """),
                ]);
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceInclude_Windows()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    // necessary for the `net8.0-windows10.0.19041.0` TFM
                    new("Microsoft.Windows.SDK.NET.Ref", "10.0.19041.54", Files:
                    [
                        ("data/FrameworkList.xml", Encoding.UTF8.GetBytes("""
                            <FileList Name="Windows SDK .NET 6.0">
                              <!-- contents omitted -->
                            </FileList>
                            """)),
                        ("data/RuntimeList.xml", Encoding.UTF8.GetBytes("""
                            <FileList Name="Windows SDK .NET 6.0" TargetFrameworkIdentifier=".NETCoreApp" TargetFrameworkVersion="6.0" FrameworkName="Microsoft.Windows.SDK.NET.Ref">
                              <!-- contents omitted -->
                            </FileList>
                            """)),
                    ]),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
                        <RuntimeIdentifier>win-x64</RuntimeIdentifier>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0-windows10.0.19041.0</TargetFramework>
                        <RuntimeIdentifier>win-x64</RuntimeIdentifier>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InMultipleProjectFiles_ForPackageReferenceInclude()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <ProjectReference Include="lib\Library.csproj" />
                      </ItemGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("lib/Library.csproj", $"""
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <ProjectReference Include="lib\Library.csproj" />
                      </ItemGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("lib/Library.csproj", $"""
                        <Project Sdk="Microsoft.NET.Sdk">
                          <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]);
        }

        [Theory]
        [InlineData("$(SomePackageVersion")]
        [InlineData("$SomePackageVersion)")]
        [InlineData("$SomePackageVersion")]
        [InlineData("SomePackageVersion)")]
        public async Task Update_InvalidFile_DoesNotThrow(string versionString)
        {
            await TestNoChangeforProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: $"""
                    <Project Sdk="Microsoft.NET.Sdk">">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion>9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="{versionString}" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateFindsNearestNugetConfig_AndSucceeds()
        {
            //
            // this test needs a very specific setup to run, so we have to do it manually
            //
            using TemporaryDirectory tempDirectory = new();

            // the top-level NuGet.Config has a package feed that doesn't exist
            await File.WriteAllTextAsync(Path.Combine(tempDirectory.DirectoryPath, "NuGet.Config"), """
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="local-feed" value="/var/path/that/does/not/exist" />
                  </packageSources>
                </configuration>
                """
            );

            // now place the "real" test files under `src/`
            string srcDirectory = Path.Combine(tempDirectory.DirectoryPath, "src");
            Directory.CreateDirectory(srcDirectory);

            // the project file
            string projectPath = Path.Combine(srcDirectory, "project.csproj");
            await File.WriteAllTextAsync(projectPath, """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net8.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Some.Package" Version="1.0.0" />
                  </ItemGroup>
                </Project>
                """
            );
            // another NuGet.Config, but with a usable package feed
            string packageFeedLocation = Path.Combine(tempDirectory.DirectoryPath, "test-package-feed");
            Directory.CreateDirectory(packageFeedLocation);
            await File.WriteAllTextAsync(Path.Combine(srcDirectory, "NuGet.Config"), $"""
                <?xml version="1.0" encoding="utf-8"?>
                <configuration>
                  <packageSources>
                    <clear />
                    <add key="local-feed" value="{packageFeedLocation}" />
                  </packageSources>
                </configuration>
                """
            );
            // populate some packages
            foreach (MockNuGetPackage package in MockNuGetPackage.CommonPackages.Concat(
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0")
                ]))
            {
                package.WriteToDirectory(packageFeedLocation);
            }

            //
            // do the update
            //
            UpdaterWorker worker = new(new ExperimentsManager(), new TestLogger());
            await worker.RunAsync(tempDirectory.DirectoryPath, projectPath, "Some.Package", "1.0.0", "1.1.0", isTransitive: false);

            //
            // verify the update occurred
            //
            string actualProjectContents = await File.ReadAllTextAsync(projectPath);
            Assert.Contains("Version=\"1.1.0\"", actualProjectContents);
        }

        [Fact]
        public async Task UpdateReturnsEmptyArray_WhenBuildFails()
        {
            await TestNoChangeforProject("Some.Package", "9.0.1", "13.0.1",
                packages: [], // nothing specified, update will fail
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    (Path: "NuGet.config", Content: """
                        <?xml version="1.0" encoding="utf-8"?>
                        <configuration>
                          <config>
                            <add key="repositoryPath" value="./packages" />
                          </config>
                          <packageSources>
                            <clear />
                            <add key="nuget_BrokenFeed" value="https://api.nuget.org/BrokenFeed" />
                          </packageSources>
                        </configuration>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateExactMatchVersionAttribute_InProjectFile_ForPackageReferenceInclude()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                        </PropertyGroup>

                        <ItemGroup>
                            <PackageReference Include="Some.Package" Version="[9.0.1]" />
                        </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                            <TargetFramework>net8.0</TargetFramework>
                        </PropertyGroup>

                        <ItemGroup>
                            <PackageReference Include="Some.Package" Version="[13.0.1]" />
                        </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task AddPackageReference_InProjectFile_ForTransientDependency(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };
            // add transient package Some.Transient.Dependency from 5.0.1 to 5.0.2
            await TestUpdateForProject("Some.Transient.Dependency", "5.0.1", "5.0.2", isTransitive: true,
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.1.3", "net8.0", [(null, [("Some.Transient.Dependency", "5.0.1")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transient.Dependency", "5.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transient.Dependency", "5.0.2", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.1.3" />
                      </ItemGroup>

                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.1.3" />
                        <PackageReference Include="Some.Transient.Dependency" Version="5.0.2" />
                      </ItemGroup>

                    </Project>
                    """
            );
        }

        [Fact]
        public async Task TransitiveDependencyCanBeAddedWithMismatchingSdk()
        {
            await TestUpdateForProject("Some.Transitive.Package", "1.0.0", "1.0.1", isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Some.Transitive.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "99.99.999" // this version doesn't match anything that's installed
                          }
                        }
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                        <PackageReference Include="Some.Transitive.Package" Version="1.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task TransitiveDependencyCanBeAddedWithCustomMSBuildSdk()
        {
            await TestUpdateForProject("Some.Transitive.Package", "1.0.0", "1.0.1", isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Some.Transitive.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Package", "1.0.1", "net8.0"),
                    MockNuGetPackage.CreateMSBuildSdkPackage("Custom.MSBuild.Sdk", "1.2.3"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Sdk.props" Sdk="Custom.MSBuild.Sdk" />
                        </Project>
                        """),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("global.json", """
                        {
                          "sdk": {
                            "version": "99.99.999" // this version doesn't match anything that's installed
                          },
                          "msbuild-sdks": {
                            "Custom.MSBuild.Sdk": "1.2.3"
                          }
                        }
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Some.Transitive.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Transitive.Package" Version="1.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForAnalyzerPackageReferenceInclude()
        {
            // update Some.Analyzer from 3.3.0 to 3.3.4
            await TestUpdateForProject("Some.Analyzer", "3.3.0", "3.3.4",
                packages:
                [
                    MockNuGetPackage.CreateAnalyzerPackage("Some.Analyzer", "3.3.0"),
                    MockNuGetPackage.CreateAnalyzerPackage("Some.Analyzer", "3.3.4"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Analyzer" Version="3.3.0">
                          <PrivateAssets>all</PrivateAssets>
                          <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Analyzer" Version="3.3.4">
                          <PrivateAssets>all</PrivateAssets>
                          <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForMultiplePackageReferences()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.PACKAGE" Version="9.0.1" />
                        <PackageReference Update="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.PACKAGE" Version="13.0.1" />
                        <PackageReference Update="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceUpdate()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Update="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Update="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceUpdateWithSemicolon()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package2", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package2", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package;Some.Package2" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InDirectoryPackages_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateExactMatchVersionAttribute_InDirectoryPackages_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="[9.0.1]" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="[13.0.1]" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InProjectFile_ForPackageReferenceIncludeWithExactVersion()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="[$(SomePackagePackageVersion)]" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="[$(SomePackagePackageVersion)]" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateDifferentCasedPropertyValue_InProjectFile_ForPackageReferenceInclude()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(somepackagepackageversion)" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(somepackagepackageversion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InProjectFile_ForPackageReferenceInclude()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateExactMatchPropertyValue_InProjectFile_ForPackageReferenceInclude()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>[9.0.1]</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>[13.0.1]</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttributeAndPropertyValue_InProjectFile_ForMultiplePackageReferences()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InProjectFile_ForPackageReferenceUpdate()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Update="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Update="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InDirectoryProps_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateExactMatchPropertyValue_InDirectoryProps_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>[9.0.1]</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>[13.0.1]</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateVersionOverrideAttributeAndPropertyValue_InProjectFileAndDirectoryProps_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" VersionOverride="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" VersionOverride="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InDirectoryProps_ForGlobalPackageReference()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="9.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="13.0.1" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InDirectoryProps_ForGlobalPackageReference()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <GlobalPackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InDirectoryProps_ForPackageReferenceInclude()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial project
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    // initial props file
                    ("Directory.Build.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // expected project
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props file
                    ("Directory.Build.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InProps_ForPackageReferenceInclude()
        {
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial project
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="my-properties.props" />

                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    // initial props file
                    ("my-properties.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // expected project
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="my-properties.props" />

                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props file
                    ("my-properties.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InProps_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    // initial props files
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="Version.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Version.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props files
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="Version.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Version.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValue_InProps_ThenSubstituted_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    // initial props files
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="Version.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>$(NewtonsoftJsonVersion)</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Version.props", """
                        <Project>
                          <PropertyGroup>
                            <NewtonsoftJsonVersion>9.0.1</NewtonsoftJsonVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props files
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="Version.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>$(NewtonsoftJsonVersion)</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Version.props", """
                        <Project>
                          <PropertyGroup>
                            <NewtonsoftJsonVersion>13.0.1</NewtonsoftJsonVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePropertyValues_InProps_ThenRedefinedAndSubstituted_ForPackageVersion()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    // initial props files
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="Version.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>$(SomePackageVersion)</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Version.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePACKAGEVersion>9.0.1</SomePACKAGEVersion>
                            <SomePackagePackageVersion>9.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props files
                    ("Directory.Packages.props", """
                        <Project>
                          <Import Project="Version.props" />
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <SomePackagePackageVersion>$(SomePackageVersion)</SomePackagePackageVersion>
                          </PropertyGroup>

                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="$(SomePackagePackageVersion)" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Version.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePACKAGEVersion>13.0.1</SomePACKAGEVersion>
                            <SomePackagePackageVersion>13.0.1</SomePackagePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePeerDependencyWithInlineVersion()
        {
            await TestUpdateForProject("Some.Package", "2.2.0", "7.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.2.0", "net8.0", [(null, [("Peer.Package", "2.2.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net8.0", [(null, [("Peer.Package", "7.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "2.2.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "7.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.2.0" />
                        <PackageReference Include="Peer.Package" Version="2.2.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.0" />
                        <PackageReference Include="Peer.Package" Version="7.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePeerDependencyFromPropertyInSameFile()
        {
            await TestUpdateForProject("Some.Package", "2.2.0", "7.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.2.0", "net8.0", [(null, [("Peer.Package", "2.2.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net8.0", [(null, [("Peer.Package", "7.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "2.2.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "7.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion>2.2.0</SomePackageVersion>
                        <PeerPackageVersion>2.2.0</PeerPackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                        <PackageReference Include="Peer.Package" Version="$(PeerPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion>7.0.0</SomePackageVersion>
                        <PeerPackageVersion>7.0.0</PeerPackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                        <PackageReference Include="Peer.Package" Version="$(PeerPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePeerDependencyFromPropertyInDifferentFile()
        {
            await TestUpdateForProject("Some.Package", "2.2.0", "7.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.2.0", "net8.0", [(null, [("Peer.Package", "2.2.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net8.0", [(null, [("Peer.Package", "7.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "2.2.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "7.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="Versions.props" />
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                        <PackageReference Include="Peer.Package" Version="$(PeerPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Versions.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>2.2.0</SomePackageVersion>
                            <PeerPackageVersion>2.2.0</PeerPackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="Versions.props" />
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                        <PackageReference Include="Peer.Package" Version="$(PeerPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Versions.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>7.0.0</SomePackageVersion>
                            <PeerPackageVersion>7.0.0</PeerPackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatePeerDependencyWithInlineVersionAndMultipleTfms()
        {
            await TestUpdateForProject("Some.Package", "2.2.0", "7.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.2.0", "net7.0", [(null, [("Peer.Package", "2.2.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net7.0", [(null, [("Peer.Package", "7.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "2.2.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Peer.Package", "7.0.0", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.2.0" />
                        <PackageReference Include="Peer.Package" Version="2.2.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.0" />
                        <PackageReference Include="Peer.Package" Version="7.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task NoUpdateForPeerDependenciesWhichAreHigherVersion()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Transitive.Dependency", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0", [(null, [("Transitive.Dependency", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "1.1.0", "net8.0"), // we shouldn't update to this
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Transitive.Dependency" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Transitive.Dependency" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Transitive.Dependency" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.1.0" />
                            <PackageVersion Include="Transitive.Dependency" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task UpdatingToNotCompatiblePackageDoesNothing()
        {
            // can't upgrade to the newer package because of a TFM mismatch
            await TestNoChangeforProject("Some.Package", "7.0.0", "8.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "8.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatingToNotCompatiblePackageDoesNothingWithSingleOfMultileTfmNotSupported()
        {
            // can't upgrade to the newer package because one of the TFMs doesn't match
            await TestNoChangeforProject("Some.Package", "7.0.0", "8.0.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "8.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net7.0;net8.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateVersionAttribute_InProjectFile_WhereTargetFrameworksIsSelfReferential()
        {
            // update Some.Package from 9.0.1 to 13.0.1
            await TestUpdateForProject("Some.Package", "9.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "9.0.1", "netstandard2.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "netstandard2.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks Condition="!$(TargetFrameworks.Contains('net472'))">$(TargetFrameworks);net472</TargetFrameworks>
                        <TargetFrameworks Condition="!$(TargetFrameworks.Contains('net8.0'))">$(TargetFrameworks);net8.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks Condition="!$(TargetFrameworks.Contains('net472'))">$(TargetFrameworks);net472</TargetFrameworks>
                        <TargetFrameworks Condition="!$(TargetFrameworks.Contains('net8.0'))">$(TargetFrameworks);net8.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdateOfNonExistantPackageDoesNothingEvenIfTransitiveDependencyIsPresent()
        {
            // package Some.Package isn't in the project, but one of its transitive dependencies is
            await TestNoChangeforProject("Some.Package", "2.2.0", "7.0.0",
                packages:
                [
                    // these packages exist in the feed, but aren't used
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.2.0", "net8.0", [(null, [("Transitive.Dependency", "2.2.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.0", "net8.0", [(null, [("Transitive.Dependency", "7.0.0")])]),
                    // one of these is used, but we can't update to it
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "2.2.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "7.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Transitive.Dependency" Version="2.2.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task AvoidPackageDowngradeWhenUpdatingDependency()
        {
            // updating from 1.0.0 to 1.1.0 of Some.Package should not cause a downgrade warning of Some.Dependency; it
            // should be pulled along, even when the TFM is pulled from a different file.  unrelated packages are ignored
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [(null, [("Some.Dependency", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0", [(null, [("Some.Dependency", "1.1.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Dependency", "1.1.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Unrelated.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Unrelated.Package", "1.1.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <TargetFramework>$(PreferredTargetFramework)</TargetFramework>
                        <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
                        <RootNamespace />
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Package" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                            <PackageVersion Include="Unrelated.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <PropertyGroup>
                            <PreferredTargetFramework>net8.0</PreferredTargetFramework>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <TargetFramework>$(PreferredTargetFramework)</TargetFramework>
                        <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
                        <RootNamespace />
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Package" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.1.0" />
                            <PackageVersion Include="Some.Dependency" Version="1.1.0" />
                            <PackageVersion Include="Unrelated.Package" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """),
                    ("Directory.Build.props", """
                        <Project>
                          <PropertyGroup>
                            <PreferredTargetFramework>net8.0</PreferredTargetFramework>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task AddTransitiveDependencyByAddingPackageReferenceAndVersion()
        {
            await TestUpdateForProject("Some.Transitive.Dependency", "5.0.0", "5.0.2", isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.1.3", "net8.0", [(null, [("Some.Transitive.Dependency", "5.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "5.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "5.0.2", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    // initial props files
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="3.1.3" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                        <PackageReference Include="Some.Transitive.Dependency" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props files
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="3.1.3" />
                            <PackageVersion Include="Some.Transitive.Dependency" Version="5.0.2" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task PinTransitiveDependencyByAddingPackageVersion()
        {
            await TestUpdateForProject("Some.Transitive.Dependency", "5.0.0", "5.0.2", isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.1.3", "net8.0", [(null, [("Some.Transitive.Dependency", "5.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "5.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "5.0.2", "net8.0"),
                ],
                // initial
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <NoWarn>$(NoWarn);NETSDK1138</NoWarn>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    // initial props files
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="3.1.3" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                // expected
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">

                      <PropertyGroup>
                        <NoWarn>$(NoWarn);NETSDK1138</NoWarn>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageReference Include="Some.Package" />
                      </ItemGroup>

                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // expected props files
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="3.1.3" />
                            <PackageVersion Include="Some.Transitive.Dependency" Version="5.0.2" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task PropsFileNameWithDifferentCasing()
        {
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Versions.Props" />
                        </Project>
                        """),
                    // notice the uppercase 'P' in the file name
                    ("Versions.Props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>12.0.1</SomePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // no change
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // no change
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Versions.Props" />
                        </Project>
                        """),
                    // version number was updated here
                    ("Versions.Props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>13.0.1</SomePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task VersionAttributeWithDifferentCasing_VersionNumberInline()
        {
            // the version attribute in the project has an all lowercase name
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task VersionAttributeWithDifferentCasing_VersionNumberInProperty()
        {
            // the version attribute in the project has an all lowercase name
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Versions.props" />
                        </Project>
                        """),
                    ("Versions.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>12.0.1</SomePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ],
                // no change
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    // no change
                    ("Directory.Build.props", """
                        <Project>
                          <Import Project="Versions.props" />
                        </Project>
                        """),
                    // version number was updated here
                    ("Versions.props", """
                        <Project>
                          <PropertyGroup>
                            <SomePackageVersion>13.0.1</SomePackageVersion>
                          </PropertyGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task DirectoryPackagesPropsDoesCentralPackagePinningGetsUpdatedIfTransitiveFlagIsSet()
        {
            await TestUpdateForProject("Some.Package.Extensions", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.0.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.1.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                ],
                isTransitive: true,
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Build.props", "<Project />"),
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.0.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.1.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task DirectoryPackagesPropsDoesNotGetDuplicateEntryIfCentralTransitivePinningIsUsed()
        {
            await TestUpdateForProject("Some.Package.Extensions", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.0.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "1.1.0", "net7.0", [(null, [("Some.Package", "1.0.0")])]),
                ],
                isTransitive: true,
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFiles:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.1.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ],
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package.Extensions" />
                      </ItemGroup>
                    </Project>
                    """,
                additionalFilesExpected:
                [
                    ("Directory.Packages.props", """
                        <Project>
                          <PropertyGroup>
                            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
                          </PropertyGroup>
                          <ItemGroup>
                            <PackageVersion Include="Some.Package" Version="1.0.0" />
                            <PackageVersion Include="Some.Package.Extensions" Version="1.1.0" />
                          </ItemGroup>
                        </Project>
                        """)
                ]
            );
        }

        [Fact]
        public async Task PackageWithFourPartVersionCanBeUpdated()
        {
            await TestUpdateForProject("Some.Package", "1.2.3.4", "1.2.3.5",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3.4", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.3.5", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3.4" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.2.3.5" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task PackageWithOnlyBuildTargetsCanBeUpdated()
        {
            await TestUpdateForProject("Some.Package", "7.0.0", "7.1.0",
                packages:
                [
                    new("Some.Package", "7.0.0", Files: [("buildTransitive/net7.0/_._", [])]),
                    new("Some.Package", "7.1.0", Files: [("buildTransitive/net7.0/_._", [])]),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.1.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackageVersionFromPropertiesWithAndWithoutConditions()
        {
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(UseLegacyVersion7) == 'true'">7.0.1</SomePackageVersion>
                        <SomePackageVersion>12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(UseLegacyVersion7) == 'true'">7.0.1</SomePackageVersion>
                        <SomePackageVersion>13.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackageVersionFromPropertyWithConditionCheckingForEmptyString()
        {
            await TestUpdateForProject("Some.Package", "12.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "12.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(SomePackageVersion) == ''">12.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <SomePackageVersion Condition="$(SomePackageVersion) == ''">13.0.1</SomePackageVersion>
                        <SomePackageVersion Condition="$(UseLegacyVersion9) == 'true'">9.0.1</SomePackageVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatingTransitiveDependencyWithNewSolverCanUpdateJustTheTopLevelPackage()
        {
            // we've been asked to explicitly update a transitive dependency, but we can solve it by updating the top-level package instead
            await TestUpdateForProject("Transitive.Package", "7.0.0", "8.0.0",
                isTransitive: true,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0", [("net8.0", [("Transitive.Package", "[7.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "2.0.0", "net8.0", [("net8.0", [("Transitive.Package", "[8.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Package", "7.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Package", "8.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <ManagePackageVersionsCentrally>false</ManagePackageVersionsCentrally>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task NoChange_IfThereAreIncoherentVersions(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // trying to update `Transitive.Dependency` to 1.1.0 would normally pull `Some.Package` from 1.0.0 to 1.1.0,
            // but the TFM doesn't allow it
            await TestNoChangeforProject("Transitive.Dependency", "1.0.0", "1.1.0",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net7.0", [(null, [("Transitive.Dependency", "[1.0.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0", [(null, [("Transitive.Dependency", "[1.1.0]")])]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "1.0.0", "net7.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "1.1.0", "net7.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net7.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task NoChange_IfTargetFrameworkCouldNotBeEvaluated()
        {
            // Make sure we don't throw if the project's TFM is an unresolvable property
            await TestNoChangeforProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>$(PropertyThatCannotBeResolved)</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task NoChange_IfPeerDependenciesCannotBeEvaluated()
        {
            // make sure we don't throw if we find conflicting peer dependencies; this can happen in multi-tfm projects if the dependencies are too complicated to resolve
            // eventually this should be able to be resolved, but currently we can't branch on the different packages for different TFMs
            await TestNoChangeforProject("Some.Package", "1.0.0", "1.1.0",
                packages:
                [
                    // initial packages
                    new MockNuGetPackage("Some.Package", "1.0.0",
                        DependencyGroups: [
                            ("net8.0", [("Transitive.Dependency", "8.0.0")]),
                            ("net9.0", [("Transitive.Dependency", "9.0.0")])
                        ]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "8.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "9.0.0", "net9.0"),

                    // what we're trying to update to, but will fail
                    new MockNuGetPackage("Some.Package", "1.1.0",
                        DependencyGroups: [
                            ("net8.0", [("Transitive.Dependency", "8.1.0")]),
                            ("net9.0", [("Transitive.Dependency", "9.1.0")])
                        ]),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "8.1.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Transitive.Dependency", "9.1.0", "net9.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0;net9.0</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedResult: new() // success
            );
        }

        [Fact]
        public async Task ProcessingProjectWithWorkloadReferencesDoesNotFail()
        {
            // enumerating the build files will fail if the Aspire workload is not installed; this test ensures we can
            // still process the update
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst;</TargetFrameworks>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst;</TargetFrameworks>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task ProcessingProjectWithAspireDoesNotFailEvenThoughWorkloadIsNotInstalled()
        {
            // enumerating the build files will fail if the Aspire workload is not installed; this test ensures we can
            // still process the update
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                        <IsAspireHost>true</IsAspireHost>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task UnresolvablePropertyDoesNotStopOtherUpdates(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // the property `$(SomeUnresolvableProperty)` cannot be resolved
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }


        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task ProjectWithWorkloadsShouldNotFail(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // the property `$(SomeUnresolvableProperty)` cannot be resolved
            await TestUpdateForProject("Some.Package", "7.0.1", "13.0.1",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "7.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "13.0.1", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Other.Package", "1.0.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0;net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="7.0.1" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFrameworks>net8.0;net8.0-ios;net8.0-android;net8.0-macos;net8.0-maccatalyst</TargetFrameworks>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Other.Package" Version="$(SomeUnresolvableProperty)" />
                        <PackageReference Include="Some.Package" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Theory]
        [InlineData(true)]
        [InlineData(false)]
        public async Task UpdatingPackageAlsoUpdatesAnythingWithADependencyOnTheUpdatedPackage(bool useLegacyDependencySolver)
        {
            var experimentsManager = new ExperimentsManager() { UseLegacyDependencySolver = useLegacyDependencySolver };

            // updating Some.Package from 3.3.30 requires that Some.Package.Extensions also be updated
            await TestUpdateForProject("Some.Package", "3.3.30", "3.4.3",
                experimentsManager: experimentsManager,
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.3.30", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.4.0", "net8.0"), // this will be ignored
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "3.4.3", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "3.3.30", "net8.0", [(null, [("Some.Package", "[3.3.30]")])]), // the dependency version is very strict with []
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "3.4.0", "net8.0", [(null, [("Some.Package", "[3.4.0]")])]), // this will be ignored
                    MockNuGetPackage.CreateSimplePackage("Some.Package.Extensions", "3.4.3", "net8.0", [(null, [("Some.Package", "[3.4.3]")])]),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.3.30" />
                        <PackageReference Include="Some.Package.Extensions" Version="3.3.30" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="3.4.3" />
                        <PackageReference Include="Some.Package.Extensions" Version="3.4.3" />
                      </ItemGroup>
                    </Project>
                    """
            );
        }

        [Fact]
        public async Task UpdatePackageWithWhitespaceInTheXMLAttributeValue()
        {
            await TestUpdateForProject("Some.Package", "1.0.0", "1.1.0",
                packages:
                [
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"),
                    MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"),
                ],
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include=" Some.Package    " Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedProjectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include=" Some.Package    " Version="1.1.0" />
                      </ItemGroup>
                    </Project>
                    """
            );
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
                projectContents: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
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
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net8.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """,
                expectedResult: new()
                {
                    ErrorType = ErrorType.AuthenticationFailure,
                    ErrorDetails = $"({http.BaseUrl.TrimEnd('/')}/index.json)",
                }
            );
        }
    }
}
