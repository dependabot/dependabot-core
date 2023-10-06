using System.IO;
using System.Linq;
using System.Threading.Tasks;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities
{
    public class SdkPackageUpdaterHelperTests
    {
        [Fact]
        public async void DirectoryBuildFilesAreOnlyPulledInFromParentDirectories()
        {
            using var temporaryDirectory = new TemporaryDirectory();
            var filesOnDisk = new[]
            {
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
            };
            foreach (var (fileName, fileContent) in filesOnDisk)
            {
                var fullPath = Path.Join(temporaryDirectory.DirectoryPath, fileName);
                var fullDirectory = Path.GetDirectoryName(fullPath)!;
                Directory.CreateDirectory(fullDirectory);
                await File.WriteAllTextAsync(fullPath, fileContent);
            }

            var buildFiles = await MSBuildHelper.LoadBuildFiles(temporaryDirectory.DirectoryPath, $"{temporaryDirectory.DirectoryPath}/src/SomeProject.csproj");
            var actualBuildFilePaths = buildFiles.Select(f => f.RepoRelativePath.NormalizePathToUnix()).ToArray();
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
            using var temporaryDirectory = new TemporaryDirectory();
            var filesOnDisk = new[]
            {
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
            };
            foreach (var (fileName, fileContent) in filesOnDisk)
            {
                var fullPath = Path.Join(temporaryDirectory.DirectoryPath, fileName);
                var fullDirectory = Path.GetDirectoryName(fullPath)!;
                Directory.CreateDirectory(fullDirectory);
                await File.WriteAllTextAsync(fullPath, fileContent);
            }

            var buildFiles = await MSBuildHelper.LoadBuildFiles(temporaryDirectory.DirectoryPath, $"{temporaryDirectory.DirectoryPath}/{projectSubpath}SomeProject.csproj");
            var actualBuildFilePaths = buildFiles.Select(f => f.RepoRelativePath.NormalizePathToUnix()).ToArray();
            var expectedBuildFilePaths = new[]
            {
                $"{projectSubpath}SomeProject.csproj",
                $"{projectSubpath}Directory.Build.props",
            };
            Assert.Equal(expectedBuildFilePaths, actualBuildFilePaths);
            Assert.True(File.Exists($"{temporaryDirectory.DirectoryPath}/{globalJsonSubpath}global.json"), "global.json was not restored");
        }
    }
}
