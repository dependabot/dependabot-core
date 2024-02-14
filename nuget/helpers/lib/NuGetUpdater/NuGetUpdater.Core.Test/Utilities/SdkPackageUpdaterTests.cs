using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class SdkPackageUpdaterTests
{
    [Theory]
    [MemberData(nameof(GetDependencyUpdates))]
    public async Task UpdateDependency_UpdatesDependencies((string Path, string Contents)[] startingContents, (string Path, string Contents)[] expectedContents,
        string dependencyName, string previousVersion, string newDependencyVersion, bool isTransitive)
    {
        // Arrange
        using var directory = TemporaryDirectory.CreateWithContents(startingContents);
        var projectPath = Path.Combine(directory.DirectoryPath, startingContents.First().Path);
        var logger = new Logger(verbose: false);

        // Act
        await SdkPackageUpdater.UpdateDependencyAsync(directory.DirectoryPath, projectPath, dependencyName, previousVersion, newDependencyVersion, isTransitive, logger);

        // Assert
        AssertContentsEqual(expectedContents, directory);
    }

    public static IEnumerable<object[]> GetDependencyUpdates()
    {
        // Simple case
        yield return new object[]
        {
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            }, // starting contents
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                      </ItemGroup>
                    </Project>
                    """)
            }, // expected contents
            "Newtonsoft.Json", "12.0.1", "13.0.1", false // isTransitive
        };

        // Dependency package has version constraint
        yield return
        [
            new[]
            {
                (Path: "src/Project/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="AWSSDK.S3" Version="3.3.17.3" />
                        <PackageReference Include="AWSSDK.Core" Version="3.3.21.19" />
                      </ItemGroup>
                    </Project>
                    """),
            }, // starting contents
            new[]
            {
                // If a dependency has a version constraint outside of our new-version, we don't update anything
                (Path: "src/Project/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="AWSSDK.S3" Version="3.3.17.3" />
                        <PackageReference Include="AWSSDK.Core" Version="3.3.21.19" />
                      </ItemGroup>
                    </Project>
                    """),
            }, // expected contents
            "AWSSDK.Core",
            "3.3.21.19",
            "3.7.300.20",
            false // isTransitive
        ];

        // Dependency project has version constraint
        yield return
        [
            new[]
            {
                (Path: "src/Project2/Project2.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
                        <ProjectReference Include="../Project/Project.csproj" />
                      </ItemGroup>
                    </Project>
                    """),
                (Path: "src/Project/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="[12.0.1, 13.0.0)" />
                      </ItemGroup>
                    </Project>
                    """),
            }, // starting contents
            new[]
            {
                (Path: "src/Project2/Project2.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                        <ProjectReference Include="../Project/Project.csproj" />
                      </ItemGroup>
                    </Project>
                    """), // starting contents
                (Path: "src/Project/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="[12.0.1, 13.0.0)" />
                      </ItemGroup>
                    </Project>
                    """),
            }, // expected contents
            "Newtonsoft.Json",
            "12.0.1",
            "13.0.1",
            false // isTransitive
        ];

        // Multiple references
        yield return
        [
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="12.0.1" />
                        <PackageReference Include="Newtonsoft.Json">
                            <Version>12.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            }, // starting contents
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json" Version="13.0.1" />
                        <PackageReference Include="Newtonsoft.Json">
                            <Version>13.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            }, // expected contents
            "Newtonsoft.Json",
            "12.0.1",
            "13.0.1",
            false // isTransitive
        ];

        // Make sure we don't update if there are incoherent versions
        yield return
        [
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                            <TargetFramework>netcoreapp2.1</TargetFramework>
                        </PropertyGroup>
                        <ItemGroup>
                            <PackageReference Include="Microsoft.Extensions.Primitives" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Options" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Logging" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Configuration.Binder" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Configuration" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Caching.Memory" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Caching.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.Relational" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.Analyzers" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore" Version="2.2.0" />
                            <PackageReference Include="Microsoft.AspNetCore.App" Version="2.1.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="2.1.0" />
                        </ItemGroup>
                    </Project>
                    """)
            }, // starting contents
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                        <PropertyGroup>
                            <TargetFramework>netcoreapp2.1</TargetFramework>
                        </PropertyGroup>
                        <ItemGroup>
                            <PackageReference Include="Microsoft.Extensions.Primitives" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Options" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Logging" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Configuration.Binder" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Configuration.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Configuration" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Caching.Memory" Version="2.2.0" />
                            <PackageReference Include="Microsoft.Extensions.Caching.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.Relational" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.Analyzers" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.Abstractions" Version="2.2.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore" Version="2.2.0" />
                            <PackageReference Include="Microsoft.AspNetCore.App" Version="2.1.0" />
                            <PackageReference Include="Microsoft.EntityFrameworkCore.SqlServer" Version="2.1.0" />
                        </ItemGroup>
                    </Project>
                    """)
            }, // expected contents
            "Microsoft.EntityFrameworkCore.SqlServer",
            "2.1.0",
            "2.2.0",
            false // isTransitive
        ];

        // PackageReference with Version as child element
        yield return
        [
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json">
                            <Version>12.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            }, // starting contents
            new[]
            {
                (Path: "src/Project.csproj", Content: """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <PropertyGroup>
                        <TargetFramework>netstandard2.0</TargetFramework>
                      </PropertyGroup>
                      <ItemGroup>
                        <PackageReference Include="Newtonsoft.Json">
                            <Version>13.0.1</Version>
                        </PackageReference>
                      </ItemGroup>
                    </Project>
                    """)
            }, // expected contents
            "Newtonsoft.Json",
            "12.0.1",
            "13.0.1",
            false // isTransitive
        ];
    }

    private static void AssertContentsEqual((string Path, string Contents)[] expectedContents, TemporaryDirectory directory)
    {
        var actualFiles = Directory.GetFiles(directory.DirectoryPath, "*", SearchOption.AllDirectories);
        Assert.Equal(expectedContents.Length, actualFiles.Length);
        foreach (var (path, contents) in expectedContents)
        {
            var fullPath = Path.Combine(directory.DirectoryPath, path);
            Assert.True(File.Exists(fullPath));
            Assert.Equal(contents, File.ReadAllText(fullPath));
        }
    }
}
