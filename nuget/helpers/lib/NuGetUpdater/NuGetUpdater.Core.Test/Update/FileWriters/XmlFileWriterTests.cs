using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class XmlFileWriterTests : FileWriterTestsBase
{
    public override IFileWriter FileWriter => new XmlFileWriter();

    [Fact]
    public async Task SingleDependency_SingleFile_DirectUpdate()
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
            projectDiscovery: new()
            {
                FilePath = "project.csproj",
                Dependencies = [], // unused
                ImportedFiles = [],
                AdditionalFiles = [],
            },
            requiredDependencies: [new Dependency("Some.Dependency", "2.0.0", DependencyType.PackageReference)],
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
}
