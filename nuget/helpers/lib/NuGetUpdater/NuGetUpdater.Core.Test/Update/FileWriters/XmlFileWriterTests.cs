using NuGetUpdater.Core.Discover;
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
    public async Task SingleDependency_CentralPackageManagement_RangeContainsNewVersion()
    {
        // in this scenario, a prior pass updated `[1.0.0]` to `[1.1.0]` for a direct dependency and now in a higher
        // level project we need to ensure the version matches when pinning a transitive dependency
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="[1.1.0]" />
                      </ItemGroup>
                    </Project>
                    """),
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
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
                        <PackageVersion Include="Some.Dependency" Version="[1.1.0]" />
                      </ItemGroup>
                    </Project>
                    """),
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_DirectUpdate()
    {
        // update the existing version attribute
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.1.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinnedWithExistingVersion()
    {
        // add a new PackageReference element to the project; version attribute in central file needs no change
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/0.9.0"],
            requiredDependencyStrings: ["Some.Dependency/1.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinnedWithUpdatedVersion()
    {
        // add a new PackageReference element to the project and update the attribute in the central file
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.1.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinnedWithNewVersion()
    {
        // add a PackageReference element to the project and package version file
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Not.This.Dependency" Version="2.0.0" />
                        <PackageReference Update="Unrelated.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Not.This.Dependency" Version="2.0.0" />
                        <PackageReference Update="Some.Dependency" Version="1.1.0" />
                        <PackageReference Update="Unrelated.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_RangeAlreadyContainsRequiredVersion()
    {
        // the central file already pins an exact version range matching the required version; only add the
        // `PackageReference` to the project and leave the central `Version` attribute untouched
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="[1.1.0]" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="[1.1.0]" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_ExactRangeIsUpdatedPreservingRangeForm()
    {
        // the central file pins an exact version range that needs updating; the bracketed range form is preserved
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="[1.0.0]" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Not.This.Dependency" />
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="[1.1.0]" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_AddedAtFrontOfItemGroup_NonStandardIndentation()
    {
        // new `PackageReference` sorts before the existing entries, so it's added at the front of each `ItemGroup`;
        // 3-space indentation is used to ensure the new elements match the surrounding formatting
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Include="Zzz.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Zzz.Dependency" Version="2.0.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Include="Some.Dependency" />
                          <PackageReference Include="Zzz.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Some.Dependency" Version="1.1.0" />
                          <PackageReference Update="Zzz.Dependency" Version="2.0.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_AddedInMiddleOfItemGroup_NonStandardIndentation()
    {
        // new `PackageReference` sorts between the existing entries, so it's added in the middle of each `ItemGroup`;
        // 3-space indentation is used to ensure the new elements match the surrounding formatting
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Include="Aaa.Dependency" />
                          <PackageReference Include="Zzz.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Aaa.Dependency" Version="2.0.0" />
                          <PackageReference Update="Zzz.Dependency" Version="2.0.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Include="Aaa.Dependency" />
                          <PackageReference Include="Some.Dependency" />
                          <PackageReference Include="Zzz.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Aaa.Dependency" Version="2.0.0" />
                          <PackageReference Update="Some.Dependency" Version="1.1.0" />
                          <PackageReference Update="Zzz.Dependency" Version="2.0.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_AddedAtEndOfItemGroup_NonStandardIndentation()
    {
        // new `PackageReference` sorts after the existing entries, so it's added at the end of each `ItemGroup`;
        // 3-space indentation is used to ensure the new elements match the surrounding formatting
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Include="Aaa.Dependency" />
                          <PackageReference Include="Bbb.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Aaa.Dependency" Version="2.0.0" />
                          <PackageReference Update="Bbb.Dependency" Version="2.0.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Include="Aaa.Dependency" />
                          <PackageReference Include="Bbb.Dependency" />
                          <PackageReference Include="Some.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Aaa.Dependency" Version="2.0.0" />
                          <PackageReference Update="Bbb.Dependency" Version="2.0.0" />
                          <PackageReference Update="Some.Dependency" Version="1.1.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_NewItemGroupAddedToProject_NonStandardIndentation()
    {
        // the project has no `ItemGroup`, so a new one is created to hold the pinned `PackageReference`; the central
        // file's existing `Version` is updated in place. 3-space indentation is used throughout.
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                       <PropertyGroup>
                          <TargetFramework>net9.0</TargetFramework>
                       </PropertyGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Some.Dependency" Version="1.0.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                       <PropertyGroup>
                          <TargetFramework>net9.0</TargetFramework>
                       </PropertyGroup>
                       <ItemGroup>
                          <PackageReference Include="Some.Dependency" />
                       </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                       <ItemGroup>
                          <PackageReference Update="Some.Dependency" Version="1.1.0" />
                       </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_NoExistingCentralElement_ElementAddedToCentralFile()
    {
        // CPV is in use and the central file has no `<PackageReference Update=...>` elements yet; the package is being
        // pinned as a transitive dependency, so a new `<PackageReference Update=...>` element is added to the central file.
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.1.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_CentralVersionFromProperty_UpdatesProperty()
    {
        // the central `<PackageReference Update=...>` element's version is expressed via an MSBuild property; pinning
        // the transitive dependency must update the backing property rather than clobbering the `$(...)` reference
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>1.0.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="$(SomeDependencyVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <PropertyGroup>
                        <SomeDependencyVersion>1.1.0</SomeDependencyVersion>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="$(SomeDependencyVersion)" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_CentralPackagesFileFromDiscovery_ElementAddedToDiscoveredFile()
    {
        // CPV is in use with a non-conventionally-named central file (`Versions.props`) that has no
        // `<PackageReference Update=...>` elements yet; because the discovered `CentralPackagesFile` path is supplied,
        // the new central element is added to that file rather than relying on the `Packages.props` filename heuristic.
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            packageManagementSpecialFileRelativePath: "Versions.props",
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Versions.props", """
                    <Project>
                      <ItemGroup>
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Versions.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="1.1.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_NoCentralFileFound_NoUpdatePerformed()
    {
        // CPV is in use but there's no `Packages.props` file, no existing `<PackageReference Update=...>` element, and
        // no discovered `CentralPackagesFile` path, so there's no reliable location to record the version; rather than
        // writing a versionless, unresolvable `PackageReference`, no update is performed and the files are left unchanged.
        await TestNoChangeAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Versions.props", """
                    <Project>
                      <ItemGroup>
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_RangeSatisfiesBothOldAndRequired_FloorIsRaised()
    {
        // the central file pins an open range (`[1.0.0,)`) that satisfies both the old and required versions; the
        // floor must be raised to the required version rather than left untouched, otherwise resolution could fall
        // back to a now-undesired older version
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="[1.0.0,)" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" />
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task SingleDependency_CentralPackageVersions_TransitiveIsPinned_CentralElementHasNoVersionAttribute_NoUpdatePerformed()
    {
        // the matched central `<PackageReference Update=...>` element has no `Version` attribute, so there's no
        // location to record the version; rather than reporting success with a versionless, unresolvable pin, no
        // update is performed and the files are left unchanged
        await TestNoChangeAsync(
            packageManagementKind: PackageManagementKind.CentralPackageVersions,
            files: [
                ("project.csproj", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Packages.props", """
                    <Project>
                      <ItemGroup>
                        <PackageReference Update="Some.Dependency" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.1.0"]
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
    public async Task SingleDependency_SingleFile_AttributeDirectUpdate_VersionRangeFromWildCard()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="1.*" />
                        <PackageReference Include="Some.Other.Dependency" Version="8.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.1.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Ignored.Dependency" Version="7.0.0" />
                        <PackageReference Include="Some.Dependency" Version="2.*" />
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
    public async Task SingleDependency_SingleFile_NoChangeForWildCard()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.*" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/1.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.*" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
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
    public async Task SingleDependency_SingleFile_TransitiveIsPinnedInNewElement()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Transitive.Dependency/2.0.0"],
            requiredDependencyStrings: ["Transitive.Dependency/3.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
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
            packageManagementKind: PackageManagementKind.CentralPackageManagementWithTransitivePinning,
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


                          <PackageReference
                            Include="Some.Dependency"
                              Version="1.0.0" UnrelatedAttribute="arrow->is->not->replaced" />

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


                          <PackageReference
                            Include="Some.Dependency"
                              Version="2.0.0" UnrelatedAttribute="arrow->is->not->replaced" />

                        </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task FormattingIsPreserved_WhenNoChangesAreMade()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Some.Dependency" Version="1.0.0" />
                      </ItemGroup>
                    </Project>
                    """),
                ("UnrelatedFile.props", """
                    <Project>
                      <Target Name="MyTarget"
                              BeforeTargets="SomeBeforeTargets"
                              AfterTargets="SomeAfterTargets">
                        <Message Text="no space before tag close->"/>
                      </Target>
                    </Project>
                    """),
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
                    """),
                ("UnrelatedFile.props", """
                    <Project>
                      <Target Name="MyTarget"
                              BeforeTargets="SomeBeforeTargets"
                              AfterTargets="SomeAfterTargets">
                        <Message Text="no space before tag close->"/>
                      </Target>
                    </Project>
                    """),
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
                        <!-- some comment -->
                        <PackageReference Include="Some.Dependency" Version="2.0.0" />
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
    public async Task FormattingIsPreserved_InMiddleOfItemGroup_HonorsIndentation()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net10.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" Version="2.0.0" />
                        <PackageReference Include="Package.B" Version="2.0.0" />
                        <PackageReference Include="Package.D" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Package.C/1.0.0"],
            requiredDependencyStrings: ["Package.C/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net10.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" Version="2.0.0" />
                        <PackageReference Include="Package.B" Version="2.0.0" />
                        <PackageReference Include="Package.C" Version="1.1.0" />
                        <PackageReference Include="Package.D" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task FormattingIsPreserved_InMiddleOfItemGroup_HonorsIndentation_EvenWithWhitespaceOnlyLine()
    {
        // note that the blank line after Package.A isn't actually blank; it has two leading spaces
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net10.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" Version="2.0.0" />
                          
                        <PackageReference Include="Package.B" Version="2.0.0" />
                        <PackageReference Include="Package.D" Version="2.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Package.C/1.0.0"],
            requiredDependencyStrings: ["Package.C/1.1.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>net10.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Package.A" Version="2.0.0" />
                          
                        <PackageReference Include="Package.B" Version="2.0.0" />
                        <PackageReference Include="Package.C" Version="1.1.0" />
                        <PackageReference Include="Package.D" Version="2.0.0" />
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

    [Fact]
    public async Task MultipleEdits_AttributeSpansChange()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup Condition="'$(Configuration)' == 'Release'">
                        <PackageReference Include="Some.Dependency" Version="9.0.0" />
                      </ItemGroup>
                      <ItemGroup Condition="'$(Configuration)' == 'Debug'">
                        <PackageReference Include="Some.Dependency" Version="9.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/9.0.0"],
            requiredDependencyStrings: ["Some.Dependency/10.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup Condition="'$(Configuration)' == 'Release'">
                        <PackageReference Include="Some.Dependency" Version="10.0.0" />
                      </ItemGroup>
                      <ItemGroup Condition="'$(Configuration)' == 'Debug'">
                        <PackageReference Include="Some.Dependency" Version="10.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task MultipleEdits_ElementSpansChange()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup Condition="'$(Configuration)' == 'Release'">
                        <PackageReference Include="Some.Dependency">
                          <Version>9.0.0</Version>
                        </PackageReference>
                      </ItemGroup>
                      <ItemGroup Condition="'$(Configuration)' == 'Debug'">
                        <PackageReference Include="Some.Dependency">
                          <Version>9.0.0</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/9.0.0"],
            requiredDependencyStrings: ["Some.Dependency/10.0.0"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup Condition="'$(Configuration)' == 'Release'">
                        <PackageReference Include="Some.Dependency">
                          <Version>10.0.0</Version>
                        </PackageReference>
                      </ItemGroup>
                      <ItemGroup Condition="'$(Configuration)' == 'Debug'">
                        <PackageReference Include="Some.Dependency">
                          <Version>10.0.0</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task UpdatingAPinnedCentrallyManagedPackageUpdatesJustTheVersionNumberWhenDeclarationIsPresent()
    {
        await TestAsync(
            packageManagementKind: PackageManagementKind.CentralPackageManagementWithTransitivePinning,
            files: [
                ("src/project.csproj", """
                    <?xml version="1.0"?>
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <?xml version="1.0"?>
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="1.0.0" />
                        <PackageVersion Include="Unrelated.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["Some.Dependency/1.0.0"],
            requiredDependencyStrings: ["Some.Dependency/2.0.0"],
            expectedFiles: [
                ("src/project.csproj", """
                    <?xml version="1.0"?>
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="Unrelated.Dependency" />
                      </ItemGroup>
                    </Project>
                    """),
                ("Directory.Packages.props", """
                    <?xml version="1.0"?>
                    <Project>
                      <ItemGroup>
                        <PackageVersion Include="Some.Dependency" Version="2.0.0" />
                        <PackageVersion Include="Unrelated.Dependency" Version="3.0.0" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task NewReference_ItemGroupWithExistingPackageReferences_IsAdded()
    {
        await TestAsync(
            files: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Package.Not.Related" Version="1.2.3" />
                      </ItemGroup>
                      <ItemGroup>
                        <AdditionalFiles Include="some-resource.json" />
                      </ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["This.Package.Gets.Pinned/4.5.5"],
            requiredDependencyStrings: ["This.Package.Gets.Pinned/4.5.6"],
            expectedFiles: [
                ("project.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <ItemGroup>
                        <PackageReference Include="A.Package.Not.Related" Version="1.2.3" />
                        <PackageReference Include="This.Package.Gets.Pinned" Version="4.5.6" />
                      </ItemGroup>
                      <ItemGroup>
                        <AdditionalFiles Include="some-resource.json" />
                      </ItemGroup>
                    </Project>
                    """)
            ]
        );
    }

    [Fact]
    public async Task NewReference_AtStartOfItemGroup_HonorsIndentation()
    {
        // this test requires tabs and rather than deal with various editor states, a tab character is explicitly included
        var tb = '\t';
        await TestAsync(
            files: [
                ("project.csproj", $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                    {tb}<ItemGroup>
                    {tb}{tb}<AdditionalFiles Include="some-resource.json" />
                    {tb}</ItemGroup>
                    </Project>
                    """)
            ],
            initialProjectDependencyStrings: ["This.Package.Gets.Pinned/4.5.5"],
            requiredDependencyStrings: ["This.Package.Gets.Pinned/4.5.6"],
            expectedFiles: [
                ("project.csproj", $"""
                    <Project Sdk="Microsoft.NET.Sdk">
                    {tb}<ItemGroup>
                    {tb}{tb}<PackageReference Include="This.Package.Gets.Pinned" Version="4.5.6" />
                    {tb}{tb}<AdditionalFiles Include="some-resource.json" />
                    {tb}</ItemGroup>
                    </Project>
                    """)
            ]
        );
    }
}
