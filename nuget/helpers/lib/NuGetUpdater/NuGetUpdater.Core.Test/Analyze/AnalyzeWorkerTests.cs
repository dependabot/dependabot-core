using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public partial class AnalyzeWorkerTests : AnalyzeWorkerTestBase
{
    [Fact]
    public async Task FindsUpdatedVersion()
    {
        await TestAnalyzeAsync(
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis.Common", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Microsoft.CodeAnalysis.Common",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.9.2",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Microsoft.CodeAnalysis.Common", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task FindsUpdatedPeerDependencies()
    {
        await TestAnalyzeAsync(
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis", "4.0.1", DependencyType.PackageReference),
                            new("Microsoft.CodeAnalysis.Workspaces.Common", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Microsoft.CodeAnalysis",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.9.2",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Microsoft.CodeAnalysis", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                    new("Microsoft.CodeAnalysis.Workspaces.Common", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task DeterminesMultiPropertyVersion()
    {
        var evaluationResult = new EvaluationResult(EvaluationResultType.Success, "$(RoslynPackageVersion)", "4.0.1", "RoslynPackageVersion", ErrorMessage: null);
        await TestAnalyzeAsync(
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis.Common", "4.0.1", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                    new()
                    {
                        FilePath = "./project2.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis.Workspaces.Common", "4.0.1", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Microsoft.CodeAnalysis.Common",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.9.2",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = true,
                UpdatedDependencies = [
                    new("Microsoft.CodeAnalysis.Common", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                    new("Microsoft.CodeAnalysis.Workspaces.Common", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task FailsToUpdateMultiPropertyVersion()
    {
        // Roslyn packages and System.Memory happen to share some versions but would fail to update in sync with each other.
        var evaluationResult = new EvaluationResult(EvaluationResultType.Success, "$(RoslynPackageVersion)", "4.5.0", "RoslynPackageVersion", ErrorMessage: null);
        await TestAnalyzeAsync(
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis.Common", "4.5.0", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                    new()
                    {
                        FilePath = "./project2.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("System.Memory", "4.5.0", DependencyType.PackageReference, EvaluationResult: evaluationResult, TargetFrameworks: ["net8.0"]),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Microsoft.CodeAnalysis.Common",
                Version = "4.5.0",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.5.0",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = true,
                UpdatedDependencies = [],
            }
        );
    }


    [Fact]
    public async Task ReturnsUpToDate_ForMissingVersionProperty()
    {
        await TestAnalyzeAsync(
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis.Common", "$(MissingPackageVersion)", DependencyType.PackageReference, EvaluationResult: new EvaluationResult(EvaluationResultType.PropertyNotFound, "$(MissingPackageVersion)", "$(MissingPackageVersion)", "$(MissingPackageVersion)", ErrorMessage: null)),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Microsoft.CodeAnalysis",
                Version = "$(MissingPackageVersion)",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "$(MissingPackageVersion)",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [],
            }
        );
    }

    [Fact]
    public async Task ReturnsUpToDate_ForMissingDependency()
    {
        await TestAnalyzeAsync(
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Microsoft.CodeAnalysis.Common", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Microsoft.CodeAnalysis",
                Version = "4.0.1",
                IgnoredVersions = [Requirement.Parse("> 4.9.2")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "4.0.1",
                CanUpdate = false,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [],
            }
        );
    }
}
