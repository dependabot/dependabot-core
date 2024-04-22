using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public partial class AnalyzeWorkerTests : AnalyzeWorkerTestBase
{
    [Fact]
    public async Task FindsUpdatedVersion()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.0.0", "net8.0"), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.1.0", "net8.0"), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "1.2.0", "net8.0"), // `IgnoredVersions` should prevent this from being selected
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "1.0.0", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
                Version = "1.0.0",
                IgnoredVersions = [Requirement.Parse("> 1.1.0")],
                IsVulnerable = false,
                Vulnerabilities = [],
            },
            expectedResult: new()
            {
                UpdatedVersion = "1.1.0",
                CanUpdate = true,
                VersionComesFromMultiDependencyProperty = false,
                UpdatedDependencies = [
                    new("Some.Package", "1.1.0", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task FindsUpdatedPeerDependencies()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "4.0.1", DependencyType.PackageReference),
                            new("Some.Transitive.Dependency", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
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
                    new("Some.Package", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                    new("Some.Transitive.Dependency", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task DeterminesMultiPropertyVersion()
    {
        var evaluationResult = new EvaluationResult(EvaluationResultType.Success, "$(SomePackageVersion)", "4.0.1", "SomePackageVersion", ErrorMessage: null);
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "4.0.1", DependencyType.PackageReference, EvaluationResult: evaluationResult),
                        ],
                    },
                    new()
                    {
                        FilePath = "./project2.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Package", "4.0.1", DependencyType.PackageReference, EvaluationResult: evaluationResult),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Transitive.Dependency",
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
                    new("Some.Package", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                    new("Some.Transitive.Dependency", "4.9.2", DependencyType.Unknown, TargetFrameworks: ["net8.0"]),
                ],
            }
        );
    }

    [Fact]
    public async Task ReturnsUpToDate_ForMissingVersionProperty()
    {
        await TestAnalyzeAsync(
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "$(MissingPackageVersion)", DependencyType.PackageReference, EvaluationResult: new EvaluationResult(EvaluationResultType.PropertyNotFound, "$(MissingPackageVersion)", "$(MissingPackageVersion)", "$(MissingPackageVersion)", ErrorMessage: null)),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
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
            packages:
            [
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.0.1", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.0.1]")])]), // initially this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.2", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.2]")])]), // should update to this
                MockNuGetPackage.CreateSimplePackage("Some.Package", "4.9.3", "net8.0", [(null, [("Some.Transitive.Dependency", "[4.9.3]")])]), // will not update this far
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.0.1", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.2", "net8.0"),
                MockNuGetPackage.CreateSimplePackage("Some.Transitive.Dependency", "4.9.3", "net8.0"),
            ],
            discovery: new()
            {
                Path = "/",
                Projects = [
                    new()
                    {
                        FilePath = "./project.csproj",
                        TargetFrameworks = ["net8.0"],
                        Dependencies = [
                            new("Some.Transitive.Dependency", "4.0.1", DependencyType.PackageReference),
                        ],
                    },
                ],
            },
            dependencyInfo: new()
            {
                Name = "Some.Package",
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
