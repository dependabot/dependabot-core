using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class ProjectHelperTests : TestBase
{
    [Theory]
    [MemberData(nameof(AdditionalFile))]
    public async Task GetAdditionalFilesFromProject(string projectPath, (string Name, string Content)[] files, string[] expectedAdditionalFiles)
    {
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(files);
        var fullProjectPath = Path.Join(tempDirectory.DirectoryPath, projectPath);

        var actualAdditionalFiles = ProjectHelper.GetAllAdditionalFilesFromProject(fullProjectPath, ProjectHelper.PathFormat.Relative);
        AssertEx.Equal(expectedAdditionalFiles, actualAdditionalFiles);
    }

    public static IEnumerable<object[]> AdditionalFile()
    {
        // no additional files
        yield return
        [
            // project path
            "src/project.csproj",
            // files
            new[]
            {
                ("src/project.csproj", """
                    <Project>
                    </Project>
                    """)
            },
            // expected additional files
            Array.Empty<string>()
        ];

        // files with relative paths
        yield return
        [
            // project path
            "src/project.csproj",
            // files
            new[]
            {
                ("src/project.csproj", """
                    <Project>
                      <ItemGroup>
                        <None Include="..\unexpected-path\packages.config" />
                      </ItemGroup>
                    </Project>
                    """),
                ("unexpected-path/packages.config", """
                    <packages></packages>
                    """)
            },
            // expected additional files
            new[]
            {
                "../unexpected-path/packages.config"
            }
        ];
    }
}
