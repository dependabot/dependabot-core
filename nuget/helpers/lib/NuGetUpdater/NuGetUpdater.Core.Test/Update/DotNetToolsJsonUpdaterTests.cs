using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class DotNetToolsJsonUpdaterTests
{
    [Fact]
    public async Task UpdateDependency_MaintainComments()
    {
        await TestAsync(
            dotnetToolsContent: """
                {
                  // this is a comment
                  "version": 1,
                  "isRoot": true,
                  "tools": {
                    "some.dotnet.tool": {
                      // this is a deep comment
                      "version": "1.0.0",
                      "commands": [
                        "some.dotnet.tool"
                      ]
                    },
                    "some-other-tool": {
                      "version": "2.1.3",
                      "commands": [
                        "some-other-tool"
                      ]
                    }
                  }
                }
                """,
            dependencyName: "Some.DotNet.Tool",
            previousDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            expectedUpdatedDotnetToolsContent: """
                {
                  // this is a comment
                  "version": 1,
                  "isRoot": true,
                  "tools": {
                    "some.dotnet.tool": {
                      // this is a deep comment
                      "version": "1.1.0",
                      "commands": [
                        "some.dotnet.tool"
                      ]
                    },
                    "some-other-tool": {
                      "version": "2.1.3",
                      "commands": [
                        "some-other-tool"
                      ]
                    }
                  }
                }
                """
        );
    }

    [Fact]
    public async Task UpdateDependency_TrailingCommaInOriginal()
    {
        await TestAsync(
            dotnetToolsContent: """
                {
                  "version": 1,
                  "isRoot": true,
                  "tools": {
                    "some.dotnet.tool": {
                      "version": "1.0.0",
                      "commands": [
                        "some.dotnet.tool"
                      ],
                    },
                    "some-other-tool": {
                      "version": "2.1.3",
                      "commands": [
                        "some-other-tool"
                      ],
                    }
                  }
                }
                """,
            dependencyName: "Some.DotNet.Tool",
            previousDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            expectedUpdatedDotnetToolsContent: """
                {
                  "version": 1,
                  "isRoot": true,
                  "tools": {
                    "some.dotnet.tool": {
                      "version": "1.1.0",
                      "commands": [
                        "some.dotnet.tool"
                      ]
                    },
                    "some-other-tool": {
                      "version": "2.1.3",
                      "commands": [
                        "some-other-tool"
                      ]
                    }
                  }
                }
                """
        );
    }

    [Fact]
    public async Task MissingDependency_NoUpdatePerformed()
    {
        await TestAsync(
            dotnetToolsContent: """
                {
                  "version": 1,
                  "isRoot": true,
                  "tools": {
                    "some-other-tool": {
                      "version": "2.1.3",
                      "commands": [
                        "some-other-tool"
                      ]
                    }
                  }
                }
                """,
            dependencyName: "Some.DotNet.Tool",
            previousDependencyVersion: "1.0.0",
            newDependencyVersion: "1.1.0",
            expectedUpdatedDotnetToolsContent: """
                {
                  "version": 1,
                  "isRoot": true,
                  "tools": {
                    "some-other-tool": {
                      "version": "2.1.3",
                      "commands": [
                        "some-other-tool"
                      ]
                    }
                  }
                }
                """
        );
    }

    private async Task TestAsync(
        string dotnetToolsContent,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        string expectedUpdatedDotnetToolsContent,
        string workspaceDirectory = "/",
        string dotnetToolsJsonPath = ".config/dotnet-tools.json"
    )
    {
        // arrange
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            (dotnetToolsJsonPath, dotnetToolsContent)
        );
        var logger = new TestLogger();

        // act
        var updatedFilePath = await DotNetToolsJsonUpdater.UpdateDependencyAsync(tempDir.DirectoryPath, workspaceDirectory, dependencyName, previousDependencyVersion, newDependencyVersion, logger);

        // assert
        var expectedUpdateToHappen = dotnetToolsContent.Replace("\r", "") != expectedUpdatedDotnetToolsContent.Replace("\r", "");
        if (expectedUpdateToHappen)
        {
            Assert.NotNull(updatedFilePath);
            var relativeUpdatedFilePath = Path.GetRelativePath(tempDir.DirectoryPath, updatedFilePath).NormalizePathToUnix();
            Assert.Equal(dotnetToolsJsonPath, relativeUpdatedFilePath);
        }

        var actualFileContents = await tempDir.ReadFileContentsAsync([dotnetToolsJsonPath]);
        var actualContent = actualFileContents.Single().Contents.Replace("\r", "");
        Assert.Equal(expectedUpdatedDotnetToolsContent.Replace("\r", ""), actualContent);
    }
}
