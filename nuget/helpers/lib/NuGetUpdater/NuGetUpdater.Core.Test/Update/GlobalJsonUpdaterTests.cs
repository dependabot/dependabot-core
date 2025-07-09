using Xunit;

namespace NuGetUpdater.Core.Test.Update;

public class GlobalJsonUpdaterTests
{
    [Fact]
    public async Task UpdateDependency_MaintainComments()
    {
        await TestAsync(
            globalJsonContent: """
                {
                  // this is a comment
                  "sdk": {
                    "version": "6.0.405",
                    "rollForward": "latestPatch"
                  },
                  "msbuild-sdks": {
                    // this is a deep comment
                    "Some.MSBuild.Sdk": "3.2.0"
                  }
                }
                """,
            dependencyName: "Some.MSBuild.Sdk",
            previousDependencyVersion: "3.2.0",
            newDependencyVersion: "4.1.0",
            expectedUpdatedGlobalJsonContent: """
                {
                  // this is a comment
                  "sdk": {
                    "version": "6.0.405",
                    "rollForward": "latestPatch"
                  },
                  "msbuild-sdks": {
                    // this is a deep comment
                    "Some.MSBuild.Sdk": "4.1.0"
                  }
                }
                """
        );
    }

    [Fact]
    public async Task UpdateDependency_TrailingCommaInOriginal()
    {
        await TestAsync(
            globalJsonContent: """
                {
                  "sdk": {
                    "version": "6.0.405",
                    "rollForward": "latestPatch"
                  },
                  "msbuild-sdks": {
                    "Some.MSBuild.Sdk": "3.2.0"
                  },
                }
                """,
            dependencyName: "Some.MSBuild.Sdk",
            previousDependencyVersion: "3.2.0",
            newDependencyVersion: "4.1.0",
            expectedUpdatedGlobalJsonContent: """
                {
                  "sdk": {
                    "version": "6.0.405",
                    "rollForward": "latestPatch"
                  },
                  "msbuild-sdks": {
                    "Some.MSBuild.Sdk": "4.1.0"
                  }
                }
                """
        );
    }

    [Fact]
    public async Task MissingDependency_NoUpdatePerformed()
    {
        await TestAsync(
            globalJsonContent: """
                {
                  "sdk": {
                    "version": "6.0.405",
                    "rollForward": "latestPatch"
                  },
                  "msbuild-sdks": {
                    "Some.MSBuild.Sdk": "3.2.0"
                  }
                }
                """,
            dependencyName: "Some.Unrelated.MSBuild.Sdk",
            previousDependencyVersion: "1.0.0",
            newDependencyVersion: "2.0.0",
            expectedUpdatedGlobalJsonContent: """
                {
                  "sdk": {
                    "version": "6.0.405",
                    "rollForward": "latestPatch"
                  },
                  "msbuild-sdks": {
                    "Some.MSBuild.Sdk": "3.2.0"
                  }
                }
                """
        );
    }

    private async Task TestAsync(
        string globalJsonContent,
        string dependencyName,
        string previousDependencyVersion,
        string newDependencyVersion,
        string expectedUpdatedGlobalJsonContent,
        string workspaceDirectory = "/",
        string globalJsonPath = "global.json"
    )
    {
        // arrange
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync(
            (globalJsonPath, globalJsonContent)
        );
        var logger = new TestLogger();

        // act
        var updatedFilePath = await GlobalJsonUpdater.UpdateDependencyAsync(tempDir.DirectoryPath, workspaceDirectory, dependencyName, previousDependencyVersion, newDependencyVersion, logger);

        // assert
        var expectedUpdateToHappen = globalJsonContent.Replace("\r", "") != expectedUpdatedGlobalJsonContent.Replace("\r", "");
        if (expectedUpdateToHappen)
        {
            Assert.NotNull(updatedFilePath);
            var relativeUpdatedFilePath = Path.GetRelativePath(tempDir.DirectoryPath, updatedFilePath).NormalizePathToUnix();
            Assert.Equal(globalJsonPath, relativeUpdatedFilePath);
        }

        var actualFileContents = await tempDir.ReadFileContentsAsync([globalJsonPath]);
        var actualContent = actualFileContents.Single().Contents.Replace("\r", "");
        Assert.Equal(expectedUpdatedGlobalJsonContent.Replace("\r", ""), actualContent);
    }
}
