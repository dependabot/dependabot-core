using System.Diagnostics.CodeAnalysis;
using System.Text.RegularExpressions;

using Microsoft.Language.Xml;

using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Files;

public class ProjectBuildFileTests
{
    [StringSyntax(StringSyntaxAttribute.Xml)]
    const string ProjectCsProj = """
        <Project Sdk="Microsoft.NET.Sdk">
          <PropertyGroup>
            <OutputType>Exe</OutputType>
            <TargetFramework>net7.0</TargetFramework>
          </PropertyGroup>
          <ItemGroup>
            <ProjectReference Include=".\Library\Library.csproj" />
          </ItemGroup>
          <ItemGroup>
            <PackageReference Include="GuiLabs.Language.Xml" Version="1.2.60" />
            <PackageReference Include="Microsoft.CodeAnalysis.CSharp" />
            <PackageReference Update="Newtonsoft.Json" VersionOverride="13.0.3" />
          </ItemGroup>
        </Project>
        """;

    [StringSyntax(StringSyntaxAttribute.Xml)]
    const string EmptyProject = """
        <Project>
        </Project>
        """;

    [StringSyntax(StringSyntaxAttribute.Xml)]
    const string DirectoryPackagesProps = """
        <Project>
          <PropertyGroup>
            <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
            <CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>
          </PropertyGroup>
          <ItemGroup>
            <GlobalPackageReference Include="Microsoft.CodeAnalysis.Common" Version="$(RoslynVersion)" />
            <PackageVersion Include="Newtonsoft.Json" VersionOverride="13.0.1" />
          </ItemGroup>
        </Project>
        """;

    private static ProjectBuildFile GetBuildFile(string contents, string filename) => new(
        basePath: "/",
        path: $"/{filename}",
        contents: Parser.ParseText(contents));

    [Fact]
    public void ProjectCsProj_GetDependencies_ReturnsDependencies()
    {
        var expectedDependencies = new List<Dependency>
        {
            new("Microsoft.NET.Sdk", null, DependencyType.MSBuildSdk),
            new("GuiLabs.Language.Xml", "1.2.60", DependencyType.PackageReference),
            new("Microsoft.CodeAnalysis.CSharp", null, DependencyType.PackageReference),
            new("Newtonsoft.Json", "13.0.3", DependencyType.PackageReference, IsUpdate: true, IsOverride: true)
        };

        var buildFile = GetBuildFile(ProjectCsProj, "Project.csproj");

        var dependencies = buildFile.GetDependencies();

        AssertEx.Equal(expectedDependencies, dependencies);
    }

    [Fact]
    public void ProjectCsProj_ReferencedProjectPaths_ReturnsPaths()
    {
        var expectedReferencedProjectPaths = new List<string>
        {
            "/Library/Library.csproj"
        };

        var buildFile = GetBuildFile(ProjectCsProj, "Project.csproj");

        var referencedProjectPaths = buildFile.GetReferencedProjectPaths()
            .Select(p => Regex.IsMatch(p, @"^[A-Z]:\\") ? "/" + p.Substring(@"C:\".Length) : p) // remove drive letter when testing on Windows
            .Select(p => p.NormalizePathToUnix());

        Assert.Equal(expectedReferencedProjectPaths, referencedProjectPaths);
    }

    [Fact]
    public void DirectoryPackagesProps_GetDependencies_ReturnsDependencies()
    {
        var expectedDependencies = new List<Dependency>
        {
            new("Microsoft.CodeAnalysis.Common", "$(RoslynVersion)", DependencyType.GlobalPackageReference),
            new("Newtonsoft.Json", "13.0.1", DependencyType.PackageVersion, IsOverride: true)
        };

        var buildFile = GetBuildFile(DirectoryPackagesProps, "Directory.Packages.props");

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }

    [Fact]
    public void DirectoryPackagesProps_Properties_ReturnsProperties()
    {
        var expectedProperties = new List<KeyValuePair<string, string>>
        {
            new("ManagePackageVersionsCentrally", "true"),
            new("CentralPackageTransitivePinningEnabled", "true")
        };

        var buildFile = GetBuildFile(DirectoryPackagesProps, "Directory.Packages.props");

        var properties = buildFile.GetProperties();

        Assert.Equal(expectedProperties, properties);
    }

    [Fact]
    public void EmptyProject_GetDependencies_ReturnsNoDependencies()
    {
        var expectedDependencies = Enumerable.Empty<Dependency>();

        var buildFile = GetBuildFile(EmptyProject, "project.csproj");

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }

    [Theory]
    // no change made
    [InlineData(
        // language=csproj
        @"<Project><ItemGroup><Reference><HintPath>path\to\file.dll</HintPath></Reference></ItemGroup></Project>",
        // language=csproj
        @"<Project><ItemGroup><Reference><HintPath>path\to\file.dll</HintPath></Reference></ItemGroup></Project>"
    )]
    // change from `/` to `\`
    [InlineData(
        // language=csproj
        "<Project><ItemGroup><Reference><HintPath>path/to/file.dll</HintPath></Reference></ItemGroup></Project>",
        // language=csproj
        @"<Project><ItemGroup><Reference><HintPath>path\to\file.dll</HintPath></Reference></ItemGroup></Project>"
    )]
    // multiple changes made
    [InlineData(
        // language=csproj
        "<Project><ItemGroup><Reference><HintPath>path1/to1/file1.dll</HintPath></Reference><Reference><HintPath>path2/to2/file2.dll</HintPath></Reference></ItemGroup></Project>",
        // language=csproj
        @"<Project><ItemGroup><Reference><HintPath>path1\to1\file1.dll</HintPath></Reference><Reference><HintPath>path2\to2\file2.dll</HintPath></Reference></ItemGroup></Project>"
    )]
    public void ReferenceHintPathsCanBeNormalized(string originalXml, string expectedXml)
    {
        ProjectBuildFile? buildFile = GetBuildFile(originalXml, "project.csproj");
        buildFile.NormalizeDirectorySeparatorsInProject();
        Assert.Equal(expectedXml, buildFile.Contents.ToFullString());
    }
}
