using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class UpdatedDependencyListTests
{
    [Fact]
    public void GetUpdatedDependencyListFromDiscovery()
    {
        using var temp = new TemporaryDirectory();
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "a"));
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "b"));
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "c"));

        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "a", "packages.config"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "b", "packages.config"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "c", "packages.config"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "a", "project.csproj"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "b", "project.csproj"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "c", "project.csproj"), "");

        var discovery = new WorkspaceDiscoveryResult()
        {
            Path = "src",
            IsSuccess = true,
            Projects = [
                new()
                {
                    FilePath = "a/project.csproj",
                    Dependencies = [
                        new("Microsoft.Extensions.DependencyModel", "6.0.0", DependencyType.PackageReference, TargetFrameworks: ["net6.0"]),
                    ],
                    IsSuccess = true,
                    Properties = [],
                    TargetFrameworks = ["net8.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = ["packages.config"],
                },
                new()
                {
                    FilePath = "b/project.csproj",
                    Dependencies = [
                    ],
                    IsSuccess = true,
                    Properties = [],
                    TargetFrameworks = ["net8.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = ["packages.config"],
                },
                new()
                {
                    FilePath = "c/project.csproj",
                    Dependencies = [
                        new("System.Text.Json", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["net6.0"], IsTransitive: true),
                        new("Newtonsoft.Json", "13.0.1", DependencyType.PackagesConfig, TargetFrameworks: ["net6.0"]),
                    ],
                    IsSuccess = true,
                    Properties = [],
                    TargetFrameworks = ["net8.0"],
                    ReferencedProjectPaths = [],
                    ImportedFiles = [],
                    AdditionalFiles = ["packages.config"],
                }
            ]
        };
        var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discovery, pathToContents: temp.DirectoryPath);
        var expectedDependencyList = new UpdatedDependencyList()
        {
            Dependencies =
            [
                new ReportedDependency()
                {
                    Name = "Microsoft.Extensions.DependencyModel",
                    Version = "6.0.0",
                    Requirements =
                    [
                        new ReportedRequirement()
                        {
                            Requirement = "6.0.0",
                            File = "/src/a/project.csproj",
                            Groups = ["dependencies"],
                        },
                    ]
                },
                new ReportedDependency()
                {
                    Name = "System.Text.Json",
                    Version = "6.0.0",
                    Requirements = [],
                },
                new ReportedDependency()
                {
                    Name = "Newtonsoft.Json",
                    Version = "13.0.1",
                    Requirements =
                    [
                        new ReportedRequirement()
                        {
                            Requirement = "13.0.1",
                            File = "/src/c/project.csproj",
                            Groups = ["dependencies"],
                        },
                    ]
                },
            ],
            DependencyFiles = ["/src/a/packages.config", "/src/a/project.csproj", "/src/b/packages.config", "/src/b/project.csproj", "/src/c/packages.config", "/src/c/project.csproj"],
        };

        // doing JSON comparison makes this easier; we don't have to define custom record equality and we get an easy diff
        var actualJson = JsonSerializer.Serialize(updatedDependencyList);
        var expectedJson = JsonSerializer.Serialize(expectedDependencyList);
        Assert.Equal(expectedJson, actualJson);
    }

    [Fact]
    public async Task UpdatedDependencyListDeduplicatesFiles()
    {
        // arrange
        using var tempDir = new TemporaryDirectory();
        var testFiles = new[]
        {
            "Directory.Packages.props",
            "project1/project1.csproj",
            "project2/project2.csproj",
        };
        foreach (var testFile in testFiles)
        {
            var fullFilePath = Path.Join(tempDir.DirectoryPath, testFile);
            Directory.CreateDirectory(Path.GetDirectoryName(fullFilePath)!);
            await File.WriteAllTextAsync(fullFilePath, "");
        }
        var discovery = new WorkspaceDiscoveryResult()
        {
            Path = "",
            Projects = [
                new()
                {
                    FilePath = "project1/project1.csproj",
                    Dependencies = [],
                    ImportedFiles = ["../Directory.Packages.props"],
                    AdditionalFiles = [],
                },
                new()
                {
                    FilePath = "project2/project2.csproj",
                    Dependencies = [],
                    ImportedFiles = ["../Directory.Packages.props"],
                    AdditionalFiles = [],
                }
            ]
        };

        // act
        var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discovery, pathToContents: tempDir.DirectoryPath);
        var expectedDependencyList = new UpdatedDependencyList()
        {
            Dependencies = [],
            DependencyFiles = ["/Directory.Packages.props", "/project1/project1.csproj", "/project2/project2.csproj"],
        };

        // doing JSON comparison makes this easier; we don't have to define custom record equality and we get an easy diff
        var actualJson = JsonSerializer.Serialize(updatedDependencyList);
        var expectedJson = JsonSerializer.Serialize(expectedDependencyList);
        Assert.Equal(expectedJson, actualJson);
    }
}
