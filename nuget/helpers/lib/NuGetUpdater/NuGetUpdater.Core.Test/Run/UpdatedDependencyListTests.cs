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
            DependencyFiles = ["/src/a/project.csproj", "/src/b/project.csproj", "/src/c/project.csproj", "/src/a/packages.config", "/src/b/packages.config", "/src/c/packages.config"],
        };

        // doing JSON comparison makes this easier; we don't have to define custom record equality and we get an easy diff
        var actualJson = JsonSerializer.Serialize(updatedDependencyList);
        var expectedJson = JsonSerializer.Serialize(expectedDependencyList);
        Assert.Equal(expectedJson, actualJson);
    }
}
