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
        var discovery = new WorkspaceDiscoveryResult()
        {
            Path = "src",
            IsSuccess = true,
            Projects = [
                new()
                {
                    FilePath = "project.csproj",
                    Dependencies = [
                        new("Microsoft.Extensions.DependencyModel", "6.0.0", DependencyType.PackageReference, TargetFrameworks: ["net6.0"]),
                        new("System.Text.Json", "6.0.0", DependencyType.Unknown, TargetFrameworks: ["net6.0"], IsTransitive: true),
                    ],
                    IsSuccess = true,
                    Properties = [],
                    TargetFrameworks = ["net8.0"],
                    ReferencedProjectPaths = [],
                }
            ]
        };
        var updatedDependencyList = RunWorker.GetUpdatedDependencyListFromDiscovery(discovery);
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
                            File = "/src/project.csproj",
                            Groups = ["dependencies"],
                        }
                    ]
                },
                new ReportedDependency()
                {
                    Name = "System.Text.Json",
                    Version = "6.0.0",
                    Requirements = [],
                }
            ],
            DependencyFiles = ["/src/project.csproj"],
        };

        // doing JSON comparison makes this easier; we don't have to define custom record equality and we get an easy diff
        var actualJson = JsonSerializer.Serialize(updatedDependencyList);
        var expectedJson = JsonSerializer.Serialize(expectedDependencyList);
        Assert.Equal(expectedJson, actualJson);
    }
}
