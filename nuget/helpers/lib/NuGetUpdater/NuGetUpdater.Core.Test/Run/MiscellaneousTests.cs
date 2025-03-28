using System.Collections.Immutable;
using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
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

    [Theory]
    [MemberData(nameof(GetIncrementMetricData))]
    public void GetIncrementMetric(Job job, IncrementMetric expected)
    {
        var actual = RunWorker.GetIncrementMetric(job);
        var actualJson = HttpApiHandler.Serialize(actual);
        var expectedJson = HttpApiHandler.Serialize(expected);
        Assert.Equal(expectedJson, actualJson);
    }

    [Theory]
    [MemberData(nameof(GetUpdateOperationsData))]
    public void GetUpdateOperations(WorkspaceDiscoveryResult discovery, (string ProjectPath, string DependencyName)[] expectedUpdateOperations)
    {
        var updateOperations = RunWorker.GetUpdateOperations(discovery).ToArray();
        var actualUpdateOperations = updateOperations.Select(uo => (uo.ProjectPath, uo.Dependency.Name)).ToArray();
        Assert.Equal(expectedUpdateOperations, actualUpdateOperations);
    }

    [Theory]
    [InlineData("/src/project.csproj", "/src/project.csproj")] // correct casing
    [InlineData("/src/project.csproj", "/SRC/PROJECT.csproj")] // incorrect casing
    public async Task EnsureCorrectFileCasing(string filePathOnDisk, string candidatePath)
    {
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync((filePathOnDisk, "contents unimportant"));
        var actualRepoRelativePath = RunWorker.EnsureCorrectFileCasing(candidatePath, tempDir.DirectoryPath);
        Assert.Equal(filePathOnDisk, actualRepoRelativePath);
    }

    public static IEnumerable<object[]> GetUpdateOperationsData()
    {
        static ProjectDiscoveryResult GetProjectDiscovery(string filePath, params string[] dependencyNames)
        {
            return new()
            {
                FilePath = filePath,
                Dependencies = dependencyNames.Select(d => new Dependency(d, "1.0.0", DependencyType.PackageReference)).ToImmutableArray(),
                ImportedFiles = [],
                AdditionalFiles = [],
            };
        }

        yield return
        [
            new WorkspaceDiscoveryResult()
            {
                Path = "",
                Projects = [
                    GetProjectDiscovery("src/Library.csproj", "Package.B", "Package.C"),
                    GetProjectDiscovery("src/Common.csproj", "Package.A", "Package.C", "Package.D"),
                ]
            },
            new (string, string)[]
            {
                ("/src/Common.csproj", "Package.A"),
                ("/src/Library.csproj", "Package.B"),
                ("/src/Common.csproj", "Package.C"),
                ("/src/Library.csproj", "Package.C"),
                ("/src/Common.csproj", "Package.D"),
            },
        ];

        yield return
        [
            new WorkspaceDiscoveryResult()
            {
                Path = "",
                Projects = [],
                GlobalJson = new()
                {
                    FilePath = "global.json",
                    Dependencies = [
                        new("Some.MSBuild.Sdk", "1.0.0", DependencyType.MSBuildSdk)
                    ]
                },
                DotNetToolsJson = new()
                {
                    FilePath = ".config/dotnet-tools.json",
                    Dependencies = [
                        new("some-tool", "2.0.0", DependencyType.DotNetTool)
                    ]
                }
            },
            new (string, string)[]
            {
                ("/.config/dotnet-tools.json", "some-tool"),
                ("/global.json", "Some.MSBuild.Sdk"),
            }
        ];
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

    public static IEnumerable<object?[]> GetIncrementMetricData()
    {
        static Job GetJob(AllowedUpdate[] allowed, bool securityUpdatesOnly, bool updatingAPullRequest)
        {
            return new Job()
            {
                AllowedUpdates = allowed.ToImmutableArray(),
                Source = new()
                {
                    Provider = "github",
                    Repo = "some/repo"
                },
                SecurityUpdatesOnly = securityUpdatesOnly,
                UpdatingAPullRequest = updatingAPullRequest,
            };
        }

        // version update
        yield return
        [
            GetJob(
                allowed: [new AllowedUpdate() { UpdateType = UpdateType.All }],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new IncrementMetric()
            {
                Metric = "updater.started",
                Tags =
                {
                    ["operation"] = "group_update_all_versions"
                }
            }
        ];

        // version update - existing pr
        yield return
        [
            GetJob(
                allowed: [new AllowedUpdate() { UpdateType = UpdateType.All }],
                securityUpdatesOnly: false,
                updatingAPullRequest: true),
            new IncrementMetric()
            {
                Metric = "updater.started",
                Tags =
                {
                    ["operation"] = "update_version_pr"
                }
            }
        ];

        // create security pr - allowed security update
        yield return
        [
            GetJob(
                allowed: [new AllowedUpdate() { UpdateType = UpdateType.All }, new AllowedUpdate() { UpdateType = UpdateType.Security }],
                securityUpdatesOnly: false,
                updatingAPullRequest: false),
            new IncrementMetric()
            {
                Metric = "updater.started",
                Tags =
                {
                    ["operation"] = "create_security_pr"
                }
            }
        ];

        // create security pr - security only
        yield return
        [
            GetJob(
                allowed: [new AllowedUpdate() { UpdateType = UpdateType.All } ],
                securityUpdatesOnly: true,
                updatingAPullRequest: false),
            new IncrementMetric()
            {
                Metric = "updater.started",
                Tags =
                {
                    ["operation"] = "create_security_pr"
                }
            }
        ];

        // update security pr - allowed security update
        yield return
        [
            GetJob(
                allowed: [new AllowedUpdate() { UpdateType = UpdateType.All }, new AllowedUpdate() { UpdateType = UpdateType.Security } ],
                securityUpdatesOnly: false,
                updatingAPullRequest: true),
            new IncrementMetric()
            {
                Metric = "updater.started",
                Tags =
                {
                    ["operation"] = "update_security_pr"
                }
            }
        ];

        // update security pr - security only
        yield return
        [
            GetJob(
                allowed: [new AllowedUpdate() { UpdateType = UpdateType.All } ],
                securityUpdatesOnly: true,
                updatingAPullRequest: true),
            new IncrementMetric()
            {
                Metric = "updater.started",
                Tags =
                {
                    ["operation"] = "update_security_pr"
                }
            }
        ];
    }
}
