using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public partial class AnalyzeWorkerTests : AnalyzeWorkerTestBase
{
    [Fact]
    public async Task FindUpdatedVersion()
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
                FilePath = "/",
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
                UpdatedDependencies = [
                    new("Some.Package", "1.1.0", DependencyType.Unknown),
                ],
                ExpectedUpdatedDependenciesCount = 1,
            }
        );
    }
}
