using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Utilities;

using Xunit;

using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Test.Run;

public class ModifiedFilesTrackerTests
{
    [Fact]
    public async Task LockFileCreatedByDiscoveryIsNotTracked()
    {
        // Simulates the scenario where RestorePackagesWithLockFile=true but no lock file is checked in.
        // After discovery runs, a lock file is created. It should not be tracked.
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """)
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (only the .csproj exists)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Single(initialFiles);

        // Simulate discovery creating a lock file (as restore would)
        var lockFilePath = Path.Combine(tempDirectory.DirectoryPath, "packages.lock.json");
        File.WriteAllText(lockFilePath, """{"version": 1, "dependencies": {}}""");

        // Create discovery result that includes the lock file as an additional file
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = ["packages.lock.json"],
                }
            ],
        };

        // Create tracker with initial files (only .csproj)
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger);
        await tracker.StartTrackingAsync(discoveryResult);

        // The lock file should not be in the tracked contents
        Assert.DoesNotContain("packages.lock.json", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify the lock file to simulate an update
        File.WriteAllText(lockFilePath, """{"version": 1, "dependencies": {"net9.0": {"Some.Package": {"resolved": "2.0.0"}}}}""");

        // Stop tracking - should NOT report the lock file as modified
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Empty(updatedFiles);
    }

    [Fact]
    public async Task ExistingLockFileIsTrackedAndReported()
    {
        // When a lock file IS checked in, it should be tracked and reported as modified after an update
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """),
            ("packages.lock.json", """{"version": 1, "dependencies": {}}""")
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (the lock file and .csproj exist)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Equal(2, initialFiles.Count);

        // Create discovery result that includes the lock file
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = ["packages.lock.json"],
                }
            ],
        };

        // Create tracker with initial files
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger, new TestEOLMetadataProvider([]));
        await tracker.StartTrackingAsync(discoveryResult);

        // The lock file SHOULD be tracked
        Assert.Contains("packages.lock.json", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify the lock file
        var lockFilePath = Path.Combine(tempDirectory.DirectoryPath, "packages.lock.json");
        File.WriteAllText(lockFilePath, """{"version": 1, "dependencies": {"net9.0": {"Some.Package": {"resolved": "2.0.0"}}}}""");

        // Stop tracking - SHOULD report the lock file as modified
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Single(updatedFiles);
        Assert.Equal("packages.lock.json", updatedFiles[0].Name);
    }

    [Fact]
    public async Task PropsFileCreatedDuringRestoreIsNotTracked()
    {
        // Simulates the scenario where a .props file is created during restore (e.g., a build-generated file)
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """)
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (only the .csproj exists)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Single(initialFiles);

        // Simulate restore creating a .props file
        var propsFilePath = Path.Combine(tempDirectory.DirectoryPath, "Directory.Build.props");
        File.WriteAllText(propsFilePath, "<Project />");

        // Create discovery result that includes the .props file as an imported file
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = ["Directory.Build.props"],
                    AdditionalFiles = [],
                }
            ],
        };

        // Create tracker with initial files (only .csproj)
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger);
        await tracker.StartTrackingAsync(discoveryResult);

        // The props file should NOT be in the tracked contents
        Assert.DoesNotContain("Directory.Build.props", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify the props file to simulate an update
        File.WriteAllText(propsFilePath, "<Project><PropertyGroup><Foo>bar</Foo></PropertyGroup></Project>");

        // Stop tracking - should NOT report the props file as modified
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Empty(updatedFiles);
    }

    [Fact]
    public async Task ExistingPropsFileIsTrackedAndReported()
    {
        // When a .props file IS checked in, it should be tracked and reported as modified after an update
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """),
            ("Directory.Build.props", "<Project />")
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (both exist)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Equal(2, initialFiles.Count);

        // Create discovery result that includes the .props file
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = ["Directory.Build.props"],
                    AdditionalFiles = [],
                }
            ],
        };

        // Create tracker with initial files
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger, new TestEOLMetadataProvider([]));
        await tracker.StartTrackingAsync(discoveryResult);

        // The props file SHOULD be tracked
        Assert.Contains("Directory.Build.props", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify the props file
        var propsFilePath = Path.Combine(tempDirectory.DirectoryPath, "Directory.Build.props");
        File.WriteAllText(propsFilePath, "<Project><PropertyGroup><Foo>bar</Foo></PropertyGroup></Project>");

        // Stop tracking - SHOULD report the props file as modified
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Single(updatedFiles);
        Assert.Equal("Directory.Build.props", updatedFiles[0].Name);
    }

    [Fact]
    public async Task ProjectFileCreatedDuringRestoreIsNotTracked()
    {
        // Simulates the scenario where a project file appears during restore that wasn't originally present
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """)
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (only the main .csproj exists)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Single(initialFiles);

        // Simulate a second project file appearing during restore/build
        var newProjectPath = Path.Combine(tempDirectory.DirectoryPath, "generated.csproj");
        File.WriteAllText(newProjectPath, "<Project />");

        // Create discovery result that includes both projects
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                new ProjectDiscoveryResult()
                {
                    FilePath = "generated.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };

        // Create tracker with initial files (only original .csproj)
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger);
        await tracker.StartTrackingAsync(discoveryResult);

        // The generated project file should NOT be in the tracked contents
        Assert.DoesNotContain("generated.csproj", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));
        // The original project file SHOULD be tracked
        Assert.Contains("project.csproj", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify both project files
        File.WriteAllText(newProjectPath, "<Project><PropertyGroup><Foo>bar</Foo></PropertyGroup></Project>");

        // Stop tracking - should NOT report the generated project file
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Empty(updatedFiles);
    }

    [Fact]
    public async Task GlobalJsonCreatedDuringRestoreIsNotTracked()
    {
        // Simulates the scenario where a global.json file is created during restore
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """)
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (no global.json exists)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Single(initialFiles);

        // Simulate global.json being created during restore
        var globalJsonPath = Path.Combine(tempDirectory.DirectoryPath, "global.json");
        File.WriteAllText(globalJsonPath, """{"sdk": {"version": "9.0.100"}}""");

        // Create discovery result that includes global.json
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
            GlobalJson = new GlobalJsonDiscoveryResult()
            {
                FilePath = "global.json",
                Dependencies = [],
            },
        };

        // Create tracker with initial files (no global.json)
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger);
        await tracker.StartTrackingAsync(discoveryResult);

        // The global.json should NOT be in the tracked contents
        Assert.DoesNotContain("global.json", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify global.json
        File.WriteAllText(globalJsonPath, """{"sdk": {"version": "10.0.100"}}""");

        // Stop tracking - should NOT report global.json as modified
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Empty(updatedFiles);
    }

    [Fact]
    public async Task DotNetToolsJsonCreatedDuringRestoreIsNotTracked()
    {
        // Simulates the scenario where a dotnet-tools.json file is created during restore
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", """
                <Project Sdk="Microsoft.NET.Sdk">
                  <PropertyGroup>
                    <TargetFramework>net9.0</TargetFramework>
                  </PropertyGroup>
                </Project>
                """)
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new TestLogger();

        // Record initial files (no dotnet-tools.json exists)
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        Assert.Single(initialFiles);

        // Simulate dotnet-tools.json being created
        var toolsDir = Path.Combine(tempDirectory.DirectoryPath, ".config");
        Directory.CreateDirectory(toolsDir);
        var toolsJsonPath = Path.Combine(toolsDir, "dotnet-tools.json");
        File.WriteAllText(toolsJsonPath, """{"version": 1, "tools": {}}""");

        // Create discovery result that includes dotnet-tools.json
        var discoveryResult = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
            DotNetToolsJson = new DotNetToolsJsonDiscoveryResult()
            {
                FilePath = ".config/dotnet-tools.json",
                Dependencies = [],
            },
        };

        // Create tracker with initial files (no dotnet-tools.json)
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialFiles, logger);
        await tracker.StartTrackingAsync(discoveryResult);

        // The dotnet-tools.json should NOT be in the tracked contents
        Assert.DoesNotContain("dotnet-tools.json", tracker.OriginalDependencyFileContents.Keys.Select(Path.GetFileName));

        // Modify dotnet-tools.json
        File.WriteAllText(toolsJsonPath, """{"version": 1, "tools": {"dotnet-ef": {"version": "9.0.0"}}}""");

        // Stop tracking - should NOT report dotnet-tools.json as modified
        var updatedFiles = await tracker.StopTrackingAsync();
        Assert.Empty(updatedFiles);
    }

    [Fact]
    public async Task UpdatedFileUsesGitIndexLineEndings()
    {
        const string originalContent = "<Project>\r\n  <PropertyGroup />\r\n</Project>\r\n";
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", originalContent));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new StringLogger();
        var tracker = CreateTracker(repoContentsPath, new()
        {
            ["project.csproj"] = EOLType.LF,
        }, logger);
        await tracker.StartTrackingAsync(CreateDiscoveryResult());

        var projectPath = Path.Join(tempDirectory.DirectoryPath, "project.csproj");
        await File.WriteAllTextAsync(projectPath, "<Project>\r\n  <PropertyGroup>\r\n    <Version>2.0.0</Version>\r\n  </PropertyGroup>\r\n</Project>\r\n", TestContext.Current.CancellationToken);

        var updatedFiles = await tracker.StopTrackingAsync();

        var updatedFile = Assert.Single(updatedFiles);
        Assert.DoesNotContain("\r", updatedFile.Content);
        Assert.DoesNotContain("\r", await File.ReadAllTextAsync(projectPath, TestContext.Current.CancellationToken));
        Assert.Contains(
            logger.Messages,
            message => message.Contains("Updating line endings for [project.csproj] from CRLF to LF to match the Git index."));
    }

    [Fact]
    public async Task UpdatedFileUsesCRLFGitIndexLineEndings()
    {
        const string originalContent = "<Project>\n  <PropertyGroup />\n</Project>\n";
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", originalContent));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var tracker = CreateTracker(repoContentsPath, new()
        {
            ["project.csproj"] = EOLType.CRLF,
        });
        await tracker.StartTrackingAsync(CreateDiscoveryResult());

        var projectPath = Path.Join(tempDirectory.DirectoryPath, "project.csproj");
        await File.WriteAllTextAsync(projectPath, "<Project>\n  <PropertyGroup>\n    <Version>2.0.0</Version>\n  </PropertyGroup>\n</Project>\n", TestContext.Current.CancellationToken);

        var updatedFiles = await tracker.StopTrackingAsync();

        var updatedFile = Assert.Single(updatedFiles);
        Assert.DoesNotMatch("(?<!\r)\n", updatedFile.Content);
        Assert.DoesNotMatch("(?<!\r)\n", await File.ReadAllTextAsync(projectPath, TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task UpdatedFileLogsWhenLineEndingsMatchGitIndex()
    {
        const string originalContent = "<Project>\n  <PropertyGroup />\n</Project>\n";
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", originalContent));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var logger = new StringLogger();
        var tracker = CreateTracker(repoContentsPath, new()
        {
            ["project.csproj"] = EOLType.LF,
        }, logger);
        await tracker.StartTrackingAsync(CreateDiscoveryResult());

        var projectPath = Path.Join(tempDirectory.DirectoryPath, "project.csproj");
        await File.WriteAllTextAsync(projectPath, "<Project>\n  <PropertyGroup>\n    <Version>2.0.0</Version>\n  </PropertyGroup>\n</Project>\n", TestContext.Current.CancellationToken);

        await tracker.StopTrackingAsync();

        Assert.Contains(
            logger.Messages,
            message => message.Contains("Line endings for [project.csproj] already match the Git index: LF."));
    }

    [Fact]
    public async Task IndexLineEndingsDoNotCauseUnchangedFileToBeReported()
    {
        const string originalContent = "<Project>\r\n  <PropertyGroup />\r\n</Project>\r\n";
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", originalContent));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var tracker = CreateTracker(repoContentsPath, new()
        {
            ["project.csproj"] = EOLType.LF,
        });
        await tracker.StartTrackingAsync(CreateDiscoveryResult());

        var updatedFiles = await tracker.StopTrackingAsync();

        Assert.Empty(updatedFiles);
    }

    [Fact]
    public async Task UpdatedFileUsesGitIndexLineEndingsWhileOriginalContentsAreRestored()
    {
        const string originalContent = "<Project>\r\n  <PropertyGroup />\r\n</Project>\r\n";
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", originalContent));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var tracker = CreateTracker(repoContentsPath, new()
        {
            ["project.csproj"] = EOLType.LF,
        });
        await tracker.StartTrackingAsync(CreateDiscoveryResult());

        var projectPath = Path.Join(tempDirectory.DirectoryPath, "project.csproj");
        await File.WriteAllTextAsync(projectPath, "<Project>\r\n  <PropertyGroup>\r\n    <Version>2.0.0</Version>\r\n  </PropertyGroup>\r\n</Project>\r\n", TestContext.Current.CancellationToken);

        var updatedFiles = await tracker.StopTrackingAsync(restoreOriginalContents: true);

        var updatedFile = Assert.Single(updatedFiles);
        Assert.DoesNotContain("\r", updatedFile.Content);
        Assert.Equal(originalContent, await File.ReadAllTextAsync(projectPath, TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task UpdatedFilePreservesBOMWhenUsingGitIndexLineEndings()
    {
        const string originalContent = "<Project>\r\n  <PropertyGroup />\r\n</Project>\r\n";
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(("project.csproj", originalContent));
        var projectPath = Path.Join(tempDirectory.DirectoryPath, "project.csproj");
        await File.WriteAllBytesAsync(projectPath, originalContent.SetBOM(setBOM: true), TestContext.Current.CancellationToken);
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var tracker = CreateTracker(repoContentsPath, new()
        {
            ["project.csproj"] = EOLType.LF,
        });
        await tracker.StartTrackingAsync(CreateDiscoveryResult());

        await File.WriteAllTextAsync(projectPath, "<Project>\r\n  <PropertyGroup>\r\n    <Version>2.0.0</Version>\r\n  </PropertyGroup>\r\n</Project>\r\n", TestContext.Current.CancellationToken);

        var updatedFiles = await tracker.StopTrackingAsync();

        var updatedFile = Assert.Single(updatedFiles);
        Assert.Equal("base64", updatedFile.ContentEncoding);
        var rawContent = Convert.FromBase64String(updatedFile.Content);
        Assert.True(rawContent.HasBOM());
        Assert.DoesNotContain((byte)'\r', rawContent);
    }

    [Fact]
    public async Task GetInitiallyExistingFiles_FindsAllEditableFileTypes()
    {
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            ("project.csproj", "<Project />"),
            ("lib.fsproj", "<Project />"),
            ("app.vbproj", "<Project />"),
            ("Directory.Build.props", "<Project />"),
            ("Directory.Build.targets", "<Project />"),
            ("app.config", "<configuration />"),
            ("web.config", "<configuration />"),
            ("packages.config", "<packages />"),
            ("packages.lock.json", "{}"),
            ("global.json", "{}"),
            (".config/dotnet-tools.json", "{}"),
            ("readme.md", "# Readme"),
            ("src/code.cs", "class C {}")
        );

        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);

        // Should find all 11 editable file types
        Assert.Contains("project.csproj", initialFiles);
        Assert.Contains("lib.fsproj", initialFiles);
        Assert.Contains("app.vbproj", initialFiles);
        Assert.Contains("Directory.Build.props", initialFiles);
        Assert.Contains("Directory.Build.targets", initialFiles);
        Assert.Contains("app.config", initialFiles);
        Assert.Contains("web.config", initialFiles);
        Assert.Contains("packages.config", initialFiles);
        Assert.Contains("packages.lock.json", initialFiles);
        Assert.Contains("global.json", initialFiles);
        Assert.Contains(".config/dotnet-tools.json", initialFiles);

        // Should NOT find non-editable files
        Assert.DoesNotContain("readme.md", initialFiles);
        Assert.DoesNotContain("src/code.cs", initialFiles);
    }

    [Theory]
    [InlineData("global.json", true)]
    [InlineData("dotnet-tools.json", true)]
    [InlineData("project.csproj", true)]
    [InlineData("lib.fsproj", true)]
    [InlineData("app.vbproj", true)]
    [InlineData("Directory.Build.props", true)]
    [InlineData("Directory.Build.targets", true)]
    [InlineData("app.config", true)]
    [InlineData("web.config", true)]
    [InlineData("packages.config", true)]
    [InlineData("packages.lock.json", true)]
    [InlineData("readme.md", false)]
    [InlineData("nuget.config", false)]
    [InlineData("code.cs", false)]
    [InlineData("some.dll", false)]
    public void MatchesAllowedEditablePattern(string fileName, bool expected)
    {
        Assert.Equal(expected, ModifiedFilesTracker.MatchesAllowedEditablePattern(fileName));
    }

    private static ModifiedFilesTracker CreateTracker(
        DirectoryInfo repoContentsPath,
        Dictionary<string, EOLType> indexEOLs,
        ILogger? logger = null)
    {
        var initialFiles = ModifiedFilesTracker.GetInitiallyExistingFiles(repoContentsPath);
        return new ModifiedFilesTracker(
            repoContentsPath,
            initialFiles,
            logger ?? new TestLogger(),
            new TestEOLMetadataProvider(indexEOLs));
    }

    private static WorkspaceDiscoveryResult CreateDiscoveryResult()
    {
        return new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new ProjectDiscoveryResult()
                {
                    FilePath = "project.csproj",
                    Dependencies = [],
                    TargetFrameworks = ["net9.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };
    }

    private sealed class TestEOLMetadataProvider(Dictionary<string, EOLType> indexEOLs) : IEOLMetadataProvider
    {
        public Task<Dictionary<string, EOLType>> GetIndexEOLsAsync(
            DirectoryInfo repoContentsPath,
            IReadOnlyCollection<string> repoRelativePaths)
        {
            return Task.FromResult(indexEOLs);
        }
    }
}
