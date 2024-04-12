using NuGetUpdater.Core.Analyze;

using Xunit;

namespace NuGetUpdater.Core.Test.Analyze;

public partial class AnalyzeWorkerTests : AnalyzeWorkerTestBase
{
    [Fact]
    public async Task FindUpdatedVersion()
    {
        await TestAnalyzeAsync(
            discovery: new()
            {
                FilePath = "/",
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
                UpdatedDependencies = [
                    new("Microsoft.CodeAnalysis.Common", "4.9.2", DependencyType.Unknown),
                ],
                ExpectedUpdatedDependenciesCount = 1,
            }
        );
    }
}
