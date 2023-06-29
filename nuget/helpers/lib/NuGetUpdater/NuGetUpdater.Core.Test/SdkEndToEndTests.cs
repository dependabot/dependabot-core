using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test;

public class SdkEndToEndTests : EndToEndTestBase
{
    [Fact]
    public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceInclude()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="9.0.1" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact]
    public async Task UpdateVersionAttribute_InProjectFile_ForMultiplePackageReferences()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.JSON" Version="9.0.1" />
                <PackageReference Update="Newtonsoft.Json" Version="9.0.1" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.JSON" Version="13.0.1" />
                <PackageReference Update="Newtonsoft.Json" Version="13.0.1" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact]
    public async Task UpdateVersionAttribute_InProjectFile_ForPackageReferenceUpdate()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Update="Newtonsoft.Json" Version="9.0.1" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Update="Newtonsoft.Json" Version="13.0.1" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact]
    public async Task UpdateVersionAttribute_InDirectoryPackages_ForPackageVersion()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePropertyValue_InProjectFile_ForPackageReferenceInclude()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact]
    public async Task UpdateVersionAttributeAndPropertyValue_InProjectFile_ForMultiplePackageReferences()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="9.0.1" />
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact]
    public async Task UpdatePropertyValue_InProjectFile_ForPackageReferenceUpdate()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Update="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """,
            // expected
            """
            <Project Sdk="Microsoft.NET.Sdk">
              <PropertyGroup>
                <TargetFramework>netstandard2.0</TargetFramework>
                <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
              </PropertyGroup>

              <ItemGroup>
                <PackageReference Update="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
              </ItemGroup>
            </Project>
            """);
    }

    [Fact]
    public async Task UpdatePropertyValue_InDirectoryProps_ForPackageVersion()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdateVersionOverrideAttributeAndPropertyValue_InProjectFileAndDirectoryProps_ForPackageVersion()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" VersionOverride="9.0.1" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" VersionOverride="13.0.1" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdateVersionAttribute_InDirectoryProps_ForGlobalPackageReference()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>

                      <ItemGroup>
                        <GlobalPackageReference Include="Newtonsoft.Json" Version="9.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>

                      <ItemGroup>
                        <GlobalPackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePropertyValue_InDirectoryProps_ForGlobalPackageReference()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <GlobalPackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <GlobalPackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePropertyValue_InDirectoryProps_ForPackageReferenceInclude()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial project
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                // initial props file
                ("Directory.Build.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            // expected project
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                // expected props file
                ("Directory.Build.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePropertyValue_InProps_ForPackageReferenceInclude()
    {
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial project
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <Import Project="my-properties.props" />

                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                // initial props file
                ("Version.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            // expected project
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <Import Project="my-properties.props" />

                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                // expected props file
                ("Version.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePropertyValue_InProps_ForPackageVersion()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                // initial props files
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Version.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                // expected props files
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Version.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePropertyValue_InProps_ThenSubstituted_ForPackageVersion()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                // initial props files
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>$(NewtonsoftJsonVersion)</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
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
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                // expected props files
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>$(NewtonsoftJsonVersion)</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
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
            });
    }

    [Fact]
    public async Task UpdatePropertyValues_InProps_ThenRedefinedAndSubstituted_ForPackageVersion()
    {
        // update Newtonsoft.Json from 9.0.1 to 13.0.1
        await TestUpdateForProject("Newtonsoft.Json", "9.0.1", "13.0.1",
            // initial
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                // initial props files
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>$(NewtonsoftJsonVersion)</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Version.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJSONVersion>9.0.1</NewtonsoftJSONVersion>
                        <NewtonsoftJsonPackageVersion>9.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            // expected
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>

                  <ItemGroup>
                    <PackageReference Include="Newtonsoft.Json" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                // expected props files
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
                        <NewtonsoftJsonPackageVersion>$(NewtonsoftJsonVersion)</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>

                      <ItemGroup>
                        <PackageVersion Include="Newtonsoft.Json" Version="$(NewtonsoftJsonPackageVersion)" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Version.props", """
                    <Project>
                      <PropertyGroup>
                        <NewtonsoftJSONVersion>13.0.1</NewtonsoftJSONVersion>
                        <NewtonsoftJsonPackageVersion>13.0.1</NewtonsoftJsonPackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePeerDependencyWithInlineVersion()
    {
        await TestUpdateForProject("Microsoft.Extensions.Http", "2.2.0", "7.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="2.2.0" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="2.2.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="7.0.0" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="7.0.0" />
                  </ItemGroup>
                </Project>
                """);
    }

    [Fact]
    public async Task UpdatePeerDependencyFromPropertyInSameFile()
    {
        await TestUpdateForProject("Microsoft.Extensions.Http", "2.2.0", "7.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                    <MicrosoftExtensionsHttpVersion>2.2.0</MicrosoftExtensionsHttpVersion>
                    <MicrosoftExtensionsLoggingVersion>2.2.0</MicrosoftExtensionsLoggingVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="$(MicrosoftExtensionsHttpVersion)" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="$(MicrosoftExtensionsLoggingVersion)" />
                  </ItemGroup>
                </Project>
                """,
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                    <MicrosoftExtensionsHttpVersion>7.0.0</MicrosoftExtensionsHttpVersion>
                    <MicrosoftExtensionsLoggingVersion>7.0.0</MicrosoftExtensionsLoggingVersion>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="$(MicrosoftExtensionsHttpVersion)" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="$(MicrosoftExtensionsLoggingVersion)" />
                  </ItemGroup>
                </Project>
                """);
    }

    [Fact]
    public async Task UpdatePeerDependencyFromPropertyInDifferentFile()
    {
        await TestUpdateForProject("Microsoft.Extensions.Http", "2.2.0", "7.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <Import Project="Versions.props" />
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="$(MicrosoftExtensionsHttpVersion)" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="$(MicrosoftExtensionsLoggingVersion)" />
                  </ItemGroup>
                </Project>
                """,
            additionalFiles: new[]
            {
                ("Versions.props", """
                    <Project>
                      <PropertyGroup>
                        <MicrosoftExtensionsHttpVersion>2.2.0</MicrosoftExtensionsHttpVersion>
                        <MicrosoftExtensionsLoggingVersion>2.2.0</MicrosoftExtensionsLoggingVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            },
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <Import Project="Versions.props" />
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="$(MicrosoftExtensionsHttpVersion)" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="$(MicrosoftExtensionsLoggingVersion)" />
                  </ItemGroup>
                </Project>
                """,
            additionalFilesExpected: new[]
            {
                ("Versions.props", """
                    <Project>
                      <PropertyGroup>
                        <MicrosoftExtensionsHttpVersion>7.0.0</MicrosoftExtensionsHttpVersion>
                        <MicrosoftExtensionsLoggingVersion>7.0.0</MicrosoftExtensionsLoggingVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            });
    }

    [Fact]
    public async Task UpdatePeerDependencyWithInlineVersionAndMultipleTfms()
    {
        await TestUpdateForProject("Microsoft.Extensions.Http", "2.2.0", "7.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFrameworks>netstandard2.0;netstandard2.1</TargetFrameworks>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="2.2.0" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="2.2.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFrameworks>netstandard2.0;netstandard2.1</TargetFrameworks>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Http" Version="7.0.0" />
                    <PackageReference Include="Microsoft.Extensions.Logging" Version="7.0.0" />
                  </ItemGroup>
                </Project>
                """);
    }

    [Fact]
    public async Task UpdatingToNotCompatiblePackageDoesNothing()
    {
        await TestUpdateForProject("Microsoft.AspNetCore.Authentication.JwtBearer", "3.1.18", "7.0.5",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netcoreapp3.1</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="3.1.18" />
                  </ItemGroup>
                </Project>
                """,
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netcoreapp3.1</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="3.1.18" />
                  </ItemGroup>
                </Project>
                """);
    }

    [Fact]
    public async Task UpdatingToNotCompatiblePackageDoesNothingWithSingleOfMultileTfmNotSupported()
    {
        // the requested package upgrade is supported on net7.0, but not netcoreapp3.1, so we skip the whole thing
        await TestUpdateForProject("Microsoft.AspNetCore.Authentication.JwtBearer", "3.1.18", "7.0.5",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFrameworks>netcoreapp3.1;net7.0</TargetFrameworks>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="3.1.18" />
                  </ItemGroup>
                </Project>
                """,
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFrameworks>netcoreapp3.1;net7.0</TargetFrameworks>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="3.1.18" />
                  </ItemGroup>
                </Project>
                """);
    }

    [Fact]
    public async Task UpdateOfNonExistantPackageDoesNothingEvenIfTransitiveDependencyIsPresent()
    {
        // package Microsoft.Extensions.Http isn't present, but one of its transitive dependencies is
        await TestUpdateForProject("Microsoft.Extensions.Http", "2.2.0", "7.0.0",
            projectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="2.2.0" />
                  </ItemGroup>
                </Project>
                """,
            expectedProjectContents: """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>netstandard2.0</TargetFramework>
                  </PropertyGroup>
                  <ItemGroup>
                    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="2.2.0" />
                  </ItemGroup>
                </Project>
                """);
    }
}
