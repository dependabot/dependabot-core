using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;

using Xunit;

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

        // Record initial lock files (none exist yet)
        var initialLockFiles = ModifiedFilesTracker.GetExistingLockFiles(repoContentsPath);
        Assert.Empty(initialLockFiles);

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

        // Create tracker with initial lock files (empty set)
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialLockFiles, logger);
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

        // Record initial lock files (the lock file exists)
        var initialLockFiles = ModifiedFilesTracker.GetExistingLockFiles(repoContentsPath);
        Assert.Single(initialLockFiles);

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

        // Create tracker with initial lock files
        var tracker = new ModifiedFilesTracker(repoContentsPath, initialLockFiles, logger);
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
}
