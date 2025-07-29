using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class XmlFileWriterTests : FileWriterTestsBase
{
    public override IFileWriter FileWriter => new XmlFileWriter(new TestLogger());

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_ProjectHasXmlNamespace()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project ToolsVersion="15.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_IncludeAttributeHasExtraWhitespace()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="  Some.Dependency  " Version="1.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="  Some.Dependency  " Version="2.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_MultipleSemicolonSeparatedPackages()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include=" Some.Dependency ; Some.Other.Dependency " Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include=" Some.Dependency ; Some.Other.Dependency " Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_FourPartVersionNumber()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.0.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_AttributeCasingIsWrong()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" VERSION="1.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" VERSION="2.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_ExactMatchVersionRange()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="[1.0.0]" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="[2.0.0]" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_ExactMatchVersionRangeFromPropertyEvaluation()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="[$(SomeDependencyVersion)]" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="[$(SomeDependencyVersion)]" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_ExactMatchVersionRangeFromPropertyValue()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>[1.0.0]</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>[2.0.0]</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_UpdateVersionAttribute()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Update="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Update="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_UpdateVersionElement()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Update="Some.Dependency">
                          <Version>1.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Update="Some.Dependency">
                          <Version>2.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_UpdateVersionAttribute_ThroughProperty()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Update="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Update="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_DuplicateEntry_DirectUpdateForBoth()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>1.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>2.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_DuplicateEntry_DirectUpdateAndPropertyUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>$(SomeDependencyVersion)</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>$(SomeDependencyVersion)</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_GlobalPackageReference()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk" />
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <GlobalPackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <GlobalPackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <GlobalPackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk" />
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <GlobalPackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <GlobalPackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <GlobalPackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Theory]
    [InlineData("$(SomeDependencyVersion")] // missing close paren
    [InlineData("$SomeDependencyVersion)")] // missing open paren
    [InlineData("$SomeDependencyVersion")] // missing both parens
    [InlineData("SomeDependencyVersion)")] // missing expansion and open paren
    public async Task SingleDependency_SingleFile_InvalidPropertyExpansionFailsGracefully(string versionString)
    {
        await TestNoChangeAsync(
            files: [
                ("project.csproj", $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion>9.0.1</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="{versionString}" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_MissingPropertyFailsGracefully()
    {
        await TestNoChangeAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_NoChangeForNonReferencedPackage()
    {
        await TestNoChangeAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Unrelated.Dependency/2.0.0"]
        );
    }

    [Fact]
    public async Task MultiDependency_SingleFile_AttributeDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="3.0.0" />
                        <PackageReference Include="Unrelated.Dependency" Version="5.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0"
            ],
            requiredDependencyStrings: [
                "Some.Dependency/2.0.0",
                "Transitive.Dependency/4.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="4.0.0" />
                        <PackageReference Include="Unrelated.Dependency" Version="5.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task MultiDependency_SingleFile_SomeAlreadyUpToDate_FromDiscovery()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0"
            ],
            requiredDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/4.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="4.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task MultiDependency_SingleFile_UpdateOnePackage_PinAnotherPackage()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0"
            ],
            requiredDependencyStrings: [
                "Some.Dependency/2.0.0",
                "Transitive.Dependency/4.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="4.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task MultiDependency_SingleFile_SomeAlreadyUpToDate_FromXml()
    {
        // this test simulates a previous pass that updated `Some.Dependency` and now a subsequent pass is attempting that again without up-to-date discovery
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0"
            ],
            requiredDependencyStrings: [
                "Some.Dependency/2.0.0",
                "Transitive.Dependency/4.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="4.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_ElementDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>1.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency">
                          <Version>2.0.0</Version>
                        </PackageReference>
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_AttributeDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="2.0.0" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task MultiDependency_CentralPackageManagement_AttributeDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                        <PackageVersion Include="Unrelated.Dependency" Version="5.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0",
                "Unrelated.Dependency/5.0.0",
            ],
            requiredDependencyStrings: [
                "Some.Dependency/2.0.0",
                "Transitive.Dependency/4.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="2.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="4.0.0" />
                        <PackageVersion Include="Unrelated.Dependency" Version="5.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_ElementDirectUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency">
                          <Version>1.0.0</Version>
                        </PackageVersion>
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency">
                          <Version>2.0.0</Version>
                        </PackageVersion>
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_UpdateThroughPropertyWithExactMatch()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>[1.0.0]</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>[2.0.0]</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_UpdateThroughPropertyInDifferentFile()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <Import Project="Versions.props" />
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Versions.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Some.Other.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <Import Project="Versions.props" />
                      <ItemGroup>
                        <PackageVersion Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageVersion Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Versions.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributePropertyUpdate()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <UnrelatedProperty>1.0.0</UnrelatedProperty>
                        <SomeDependencyVersion>$(UnrelatedProperty)</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <UnrelatedProperty>2.0.0</UnrelatedProperty>
                        <SomeDependencyVersion>$(UnrelatedProperty)</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_AttributePropertyUpdate_PropertyNameDoesNotMatchCase()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <UnrelatedProperty>1.0.0</UnrelatedProperty>
                        <SomeDependencyVersion>$(unrelatedPROPERTY)</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(someDEPENDENCYversion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <UnrelatedProperty>2.0.0</UnrelatedProperty>
                        <SomeDependencyVersion>$(unrelatedPROPERTY)</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(someDEPENDENCYversion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_MultiplePropertiesBestFitIsUsed()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_1)' == 'true'">4.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_2)' == 'true'">5.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_1)' == 'true'">4.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                        <SomeDependencyVersion Condition="'$(UnknownProperty_2)' == 'true'">5.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_TransitiveIsPinnedAtFront()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "A.Transitive.Dependency/2.0.0",
                "Some.Dependency/1.0.0",
            ],
            requiredDependencyStrings: [
                "A.Transitive.Dependency/3.0.0",
                "Some.Dependency/1.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Transitive.Dependency" Version="3.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_SingleFile_TransitiveIsPinnedInMiddle()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/2.0.0",
            ],
            requiredDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                        <PackageReference Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_ExistingPackageVersionElement_AlreadyCorrect()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/2.0.0",
            ],
            requiredDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_ExistingPackageVersionElement_VersionOverrideNeeded()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="9.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/2.0.0",
            ],
            requiredDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" VersionOverride="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="9.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_NoExistingPackageVersionElement_VersionElementAddedAtFront()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "A.Transitive.Dependency/2.0.0",
                "Some.Dependency/1.0.0",
            ],
            requiredDependencyStrings: [
                "A.Transitive.Dependency/3.0.0",
                "Some.Dependency/1.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Transitive.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="A.Transitive.Dependency" Version="3.0.0" />
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_NoExistingPackageVersionElement_VersionElementAddedInMiddle()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/2.0.0",
            ],
            requiredDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Transitive.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageManagement_TransitiveIsPinned_NoExistingPackageVersionElement_TransitivePinningEnabled_OnlyPackagesPropsIsUpdated()
    {
        await TestAsync(
            useCentralPackageTransitivePinning: true,
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/2.0.0",
            ],
            requiredDependencyStrings: [
                "Some.Dependency/1.0.0",
                "Transitive.Dependency/3.0.0",
            ],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Transitive.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task FormattingIsPreserved_UpdateAttribute()
    {
        // the formatting of the XML is weird and should be kept
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">

                            <ItemGroup>


                          <PackageReference Include="Some.Dependency" Version="1.0.0" />

                        </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">

                            <ItemGroup>


                          <PackageReference Include="Some.Dependency" Version="2.0.0" />

                        </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task FormattingIsPreserved_CommentsArePreserved_WhenInsertingAtFirstOfList()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <!-- some comment -->
                        <PackageReference Include="Unrelated.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                        <!-- some comment -->
                        <PackageReference Include="Unrelated.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task FormattingIsPreserved_CommentsArePreserved_WhenInsertingAfterSibling()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Dependency" Version="3.0.0" /> <!-- some comment -->
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Dependency" Version="3.0.0" /> <!-- some comment -->
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task UpdateOfSdkManagedPackageCanOccurDespiteVersionReplacements()
    {
        // To avoid a unit test that's tightly coupled to the installed SDK, A list of SDK-managed packages is faked.
        // In this test the package `Test.Sdk.Managed.Package` is listed in the project as 1.0.0, but the SDK replaces
        // the version with 1.0.1 during a restore operation, so that's what the file updater thinks it's starting with.
        // The update then proceeds from 1.0.1 to 1.0.2.
        using var tempDirectory = new TemporaryDirectory();
        var packageCorrelationFile = Path.Combine(tempDirectory.DirectoryPath, "dotnet-package-correlation.json");
        await File.WriteAllTextAsync(packageCorrelationFile, """
            {
                "Runtimes": {
                    "1.0.0": {
                        "Packages": {
                            "Dependabot.App.Core.Ref": "1.0.0",
                            "Test.Sdk.Managed.Package": "1.0.0"
                        }
                    },
                    "1.0.1": {
                        "Packages": {
                            "Dependabot.App.Core.Ref": "1.0.1",
                            "Test.Sdk.Managed.Package": "1.0.1"
                        }
                    }
                }
            }
            """, TestContext.Current.CancellationToken);
        using var tempEnvironment = new TemporaryEnvironment([("DOTNET_PACKAGE_CORRELATION_FILE_PATH", packageCorrelationFile)]);

        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Test.Sdk.Managed.Package" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Test.Sdk.Managed.Package/1.0.1"],
            requiredDependencyStrings: ["Test.Sdk.Managed.Package/1.0.2"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Test.Sdk.Managed.Package" Version="1.0.2" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task NoChangesForUnsupportedInitialFile()
    {
        // the extension `.xyproj` is not supported by the file writer; it is immediately rejected
        await TestNoChangeAsync(
            files: [
                ("unsupported.xyproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Package" Version="$(SomePackageVersion)" />
                      </ItemGroup>
                    </Project
                    """),
                ("versions.props", """
                    <Project>
                      <PropertyGroup>
                        <SomePackageVersion>1.0.0</SomePackageVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Package/1.0.0"],
            requiredDependencyStrings: ["Some.Package/2.0.0"]
        );
    }

    [Fact]
    public async Task XmlDeclarationIsRetained()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="versions.props" />
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("versions.props", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="versions.props" />
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="$(SomeDependencyVersion)" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("versions.props", """
                    <?xml version="1.0" encoding="utf-8"?>
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>2.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                    </Project>
                    """)
            ]
        );
    }
}
