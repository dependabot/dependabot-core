using System.IO;
using System.Linq;
using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities
{
    public class SdkPackageUpdaterHelperTests
    {
        [Fact]
        public async Task DirectoryBuildFilesAreOnlyPulledInFromParentDirectories()
        {
            using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
                ("src/SomeProject.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="..\props\Versions.props" />
                    </Project>
                    """),
                ("src/Directory.Build.targets", """
                    <Project>
                    </Project>
                    """),
                ("props/Versions.props", """
                    <Project>
                    </Project>
                    """),
                ("Directory.Build.props", """
                    <Project>
                    </Project>
                    """),
                ("test/Directory.Build.props", """
                    <Project>
                      <!-- this file should not be loaded -->
                    </Project>
                    """)
            );
            var actualBuildFilePaths = await LoadBuildFilesFromTemp(temporaryDirectory, "src/SomeProject.csproj");
            var expectedBuildFilePaths = new[]
            {
                "src/SomeProject.csproj",
                "Directory.Build.props",
                "props/Versions.props",
                "src/Directory.Build.targets",
            };
            Assert.Equal(expectedBuildFilePaths, actualBuildFilePaths);
        }

        [Theory]
        [InlineData("", "")] // everything at root
        [InlineData("src/", "src/")] // everything in subdirectory
        [InlineData("src/", "")] // project in subdirectory, global.json at root
        public async Task BuildFileEnumerationWorksEvenWithNonSupportedSdkInGlobalJson(string projectSubpath, string globalJsonSubpath)
        {
            using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
                ($"{projectSubpath}SomeProject.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                    </Project>
                    """),
                ($"{projectSubpath}Directory.Build.props", """
                    <Project>
                    </Project>
                    """),
                ($"{globalJsonSubpath}global.json", """
                    {
                      "sdk": {
                        "version": "99.99.99"
                      }
                    }
                    """)
            );
            var actualBuildFilePaths = await LoadBuildFilesFromTemp(temporaryDirectory, $"{projectSubpath}/SomeProject.csproj");
            var expectedBuildFilePaths = new[]
            {
                $"{projectSubpath}SomeProject.csproj",
                $"{projectSubpath}Directory.Build.props",
            };
            Assert.Equal(expectedBuildFilePaths, actualBuildFilePaths);
            Assert.True(File.Exists($"{temporaryDirectory.DirectoryPath}/{globalJsonSubpath}global.json"), "global.json was not restored");
        }

        [Fact]
        public async Task BuildFileEnumerationWithNonStandardMSBuildSdkAndNonSupportedSdkVersionInGlobalJson()
        {
            using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
                ("global.json", """
                    {
                      "sdk": {
                        "version": "99.99.99"
                      },
                      "msbuild-sdks": {
                        "Microsoft.Build.NoTargets": "3.7.0"
                      }
                    }
                    """),
                ("SomeProject.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                      <Import Project="NoTargets.props" />
                    </Project>
                    """),
                ("NoTargets.props", """
                    <Project Sdk="Microsoft.Build.NoTargets">
                      <Import Project="Versions.props" />
                    </Project>
                    """),
                ("Versions.props", """
                    <Project Sdk="Microsoft.Build.NoTargets">
                    </Project>
                    """)
            );
            var actualBuildFilePaths = await LoadBuildFilesFromTemp(temporaryDirectory, "SomeProject.csproj");
            var expectedBuildFilePaths = new[]
            {
                "SomeProject.csproj",
                "NoTargets.props",
                "Versions.props",
            };
            Assert.Equal(expectedBuildFilePaths, actualBuildFilePaths);
            var globalJsonContent = await File.ReadAllTextAsync($"{temporaryDirectory.DirectoryPath}/global.json");
            Assert.Contains("99.99.99", globalJsonContent); // ensure global.json was restored
        }

        [Fact]
        public async Task BuildFileEnumerationWithUnsuccessfulImport()
        {
            using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
                ("Directory.Build.props", """
                    <Project>
                      <Import Project="file-that-does-not-exist.targets" />
                    </Project>
                    """),
                ("NonBuildingProject.csproj", """
                    <Project Sdk="Microsoft.NET.Sdk">
                    </Project>
                    """)
            );
            var actualBuildFilePaths = await LoadBuildFilesFromTemp(temporaryDirectory, "NonBuildingProject.csproj");
            var expectedBuildFilePaths = new[]
            {
                "NonBuildingProject.csproj",
                "Directory.Build.props",
            };
            Assert.Equal(expectedBuildFilePaths, actualBuildFilePaths);
        }

        [Fact]
        public async Task BuildFileEnumerationWithGlobalJsonWithComments()
        {
            using var temporaryDirectory = await TemporaryDirectory.CreateWithContentsAsync(
                ("global.json", """
                    {
                      // this is a comment
                      "msbuild-sdks": {
                        // this is a deep comment
                        "Microsoft.Build.NoTargets": "3.7.0"
                      }
                    }
                    """),
                ("NonBuildingProject.csproj", """
                    <Project Sdk="Microsoft.Build.NoTargets">
                    </Project>
                    """)
            );
            var actualBuildFilePaths = await LoadBuildFilesFromTemp(temporaryDirectory, "NonBuildingProject.csproj");
            var expectedBuildFilePaths = new[]
            {
                "NonBuildingProject.csproj",
            };
            Assert.Equal(expectedBuildFilePaths, actualBuildFilePaths);
        }

        private static async Task<string[]> LoadBuildFilesFromTemp(TemporaryDirectory temporaryDirectory, string relativeProjectPath)
        {
            var buildFiles = await MSBuildHelper.LoadBuildFiles(temporaryDirectory.DirectoryPath, $"{temporaryDirectory.DirectoryPath}/{relativeProjectPath}");
            var buildFilePaths = buildFiles.Select(f => f.RepoRelativePath.NormalizePathToUnix()).ToArray();
            return buildFilePaths;
        }
    }
}
