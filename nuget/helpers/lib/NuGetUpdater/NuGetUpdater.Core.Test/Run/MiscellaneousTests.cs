using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class MiscellaneousTests
{
    [Theory]
    [MemberData(nameof(RequirementsFromIgnoredVersionsData))]
    public void RequirementsFromIgnoredVersions(string dependencyName, Condition[] ignoreConditions, Requirement[] expectedRequirements)
    {
        var job = new Job()
        {
            Source = new()
            {
                Provider = "github",
                Repo = "some/repo"
            },
            IgnoreConditions = ignoreConditions
        };
        var actualRequirements = RunWorker.GetIgnoredRequirementsForDependency(job, dependencyName);
        var actualRequirementsStrings = string.Join("|", actualRequirements.Select(r => r.ToString()));
        var expectedRequirementsStrings = string.Join("|", expectedRequirements.Select(r => r.ToString()));
        Assert.Equal(expectedRequirementsStrings, actualRequirementsStrings);
    }

    [Theory]
    [MemberData(nameof(DependencyInfoFromJobData))]
    public void DependencyInfoFromJob(Job job, Dependency dependency, DependencyInfo expectedDependencyInfo)
    {
        var actualDependencyInfo = RunWorker.GetDependencyInfo(job, dependency);
        var expectedString = JsonSerializer.Serialize(expectedDependencyInfo, AnalyzeWorker.SerializerOptions);
        var actualString = JsonSerializer.Serialize(actualDependencyInfo, AnalyzeWorker.SerializerOptions);
        Assert.Equal(expectedString, actualString);
    }

    public static IEnumerable<object?[]> RequirementsFromIgnoredVersionsData()
    {
        yield return
        [
            // dependencyName
            "Some.Package",
            // ignoredConditions
            new Condition[]
            {
                new()
                {
                    DependencyName = "SOME.PACKAGE",
                    VersionRequirement = Requirement.Parse("> 1.2.3")
                },
                new()
                {
                    DependencyName = "some.package",
                    VersionRequirement = Requirement.Parse("<= 2.0.0")
                },
                new()
                {
                    DependencyName = "Unrelated.Package",
                    VersionRequirement = Requirement.Parse("= 3.4.5")
                }
            },
            // expectedRequirements
            new Requirement[]
            {
                new IndividualRequirement(">", NuGetVersion.Parse("1.2.3")),
                new IndividualRequirement("<=", NuGetVersion.Parse("2.0.0")),
            }
        ];

        // version requirement is null => ignore all
        yield return
        [
            // dependencyName
            "Some.Package",
            // ignoredConditions
            new Condition[]
            {
                new()
                {
                    DependencyName = "Some.Package"
                }
            },
            // expectedRequirements
            new Requirement[]
            {
                new IndividualRequirement(">", NuGetVersion.Parse("0.0.0"))
            }
        ];
    }

    public static IEnumerable<object[]> DependencyInfoFromJobData()
    {
        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "some/repo"
                },
                SecurityAdvisories = [
                    new()
                    {
                        DependencyName = "Some.Dependency",
                        AffectedVersions = [Requirement.Parse(">= 1.0.0, < 1.1.0")],
                        PatchedVersions = [Requirement.Parse("= 1.1.0")],
                        UnaffectedVersions = [Requirement.Parse("= 1.2.0")]
                    },
                    new()
                    {
                        DependencyName = "Unrelated.Dependency",
                        AffectedVersions = [Requirement.Parse(">= 1.0.0, < 99.99.99")]
                    }
                ]
            },
            // dependency
            new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
            // expectedDependencyInfo
            new DependencyInfo()
            {
                Name = "Some.Dependency",
                Version = "1.0.0",
                IsVulnerable = true,
                IgnoredVersions = [],
                Vulnerabilities = [
                    new()
                    {
                        DependencyName = "Some.Dependency",
                        PackageManager = "nuget",
                        VulnerableVersions = [Requirement.Parse(">= 1.0.0, < 1.1.0")],
                        SafeVersions = [Requirement.Parse("= 1.1.0"), Requirement.Parse("= 1.2.0")],
                    }
                ]
            }
        ];
    }
}
