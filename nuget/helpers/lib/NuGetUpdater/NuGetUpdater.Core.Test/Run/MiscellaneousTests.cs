using System.Collections.Immutable;
using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Test.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Run;

public class MiscellaneousTests
{
    [Theory]
    [MemberData(nameof(IsDependencyIgnoredTestData))]
    public void IsDependencyIgnored(Condition[] ignoreConditions, string dependencyName, string dependencyVersion, bool expectedIgnored)
    {
        // arrange
        var job = new Job()
        {
            Source = new()
            {
                Provider = "github",
                Repo = "some/repo"
            },
            IgnoreConditions = ignoreConditions,
        };

        // act
        var actualIsIgnored = job.IsDependencyIgnored(dependencyName, dependencyVersion);

        // assert
        Assert.Equal(expectedIgnored, actualIsIgnored);
    }

    public static IEnumerable<object[]> IsDependencyIgnoredTestData()
    {
        yield return
        [
            // ignoreConditions
            new[]
            {
                new Condition()
                {
                    DependencyName = "Different.Dependency",
                }
            },
            // dependencyName
            "Some.Dependency",
            // dependencyVersion
            "1.2.3",
            // expectedIgnored
            false,
        ];

        yield return
        [
            // ignoreConditions
            new[]
            {
                new Condition()
                {
                    DependencyName = "Some.Dependency",
                    VersionRequirement = Requirement.Parse("> 2.0.0"),
                }
            },
            // dependencyName
            "Some.Dependency",
            // dependencyVersion
            "1.2.3",
            // expectedIgnored
            false,
        ];

        yield return
        [
            // ignoreConditions
            new[]
            {
                new Condition()
                {
                    DependencyName = "Some.Dependency",
                    VersionRequirement = Requirement.Parse("> 1.0.0"),
                }
            },
            // dependencyName
            "Some.Dependency",
            // dependencyVersion
            "1.2.3",
            // expectedIgnored
            true,
        ];

        yield return
        [
            // ignoreConditions
            new[]
            {
                new Condition()
                {
                    DependencyName = "Some.*",
                }
            },
            // dependencyName
            "Some.Dependency",
            // dependencyVersion
            "1.2.3",
            // expectedIgnored
            true,
        ];
    }

    [Fact]
    public void DeserializeDependencyGroup()
    {
        var json = """
            {
              "name": "test-group",
              "rules": {
                "patterns": ["Test.*"],
                "exclude-patterns": ["Dependency.*"]
              }
            }
            """;
        var group = JsonSerializer.Deserialize<DependencyGroup>(json, RunWorker.SerializerOptions);
        Assert.NotNull(group);
        Assert.Equal("test-group", group.Name);
        var matcher = group.GetGroupMatcher();
        Assert.Equal(["Test.*"], matcher.Patterns);
        Assert.Equal(["Dependency.*"], matcher.ExcludePatterns);
    }

    [Fact]
    public void DeserializeDependencyGroup_UnexpectedShape()
    {
        var json = """
            {
              "name": "test-group",
              "rules": {
                "patterns": { "unexpected": 1 },
                "exclude-patterns": { "unexpected": 2 }
              }
            }
            """;
        var group = JsonSerializer.Deserialize<DependencyGroup>(json, RunWorker.SerializerOptions);
        Assert.NotNull(group);
        Assert.Equal("test-group", group.Name);
        var matcher = group.GetGroupMatcher();
        Assert.Equal([], matcher.Patterns);
        Assert.Equal([], matcher.ExcludePatterns);
    }

    [Theory]
    [MemberData(nameof(DependencyGroup_IsMatchTestData))]
    public void DependencyGroup_IsMatch(string[]? patterns, string[]? excludePatterns, string dependencyName, bool expectedMatch)
    {
        var rules = new Dictionary<string, object>();
        if (patterns is not null)
        {
            rules["patterns"] = patterns;
        }

        if (excludePatterns is not null)
        {
            rules["exclude-patterns"] = excludePatterns;
        }

        var group = new DependencyGroup()
        {
            Name = "TestGroup",
            Rules = rules,
        };
        var matcher = group.GetGroupMatcher();
        var isMatch = matcher.IsMatch(dependencyName);
        Assert.Equal(expectedMatch, isMatch);
    }

    public static IEnumerable<object?[]> DependencyGroup_IsMatchTestData()
    {
        yield return
        [
            null, // patterns
            null, // excludePatterns
            "Some.Package", // dependencyName
            true, // expectMatch
        ];

        yield return
        [
            new[] { "*" }, // patterns
            null, // excludePatterns
            "Some.Package", // dependencyName
            true, // expectMatch
        ];

        yield return
        [
            new[] { "some.*" }, // patterns
            null, // excludePatterns
            "Some.Package", // dependencyName
            true, // expectMatch
        ];

        yield return
        [
            null, // patterns
            new[] { "some.*" }, // excludePatterns
            "Some.Package", // dependencyName
            false, // expectMatch
        ];

        yield return
        [
            new[] { "*" }, // patterns
            new[] { "some.*" }, // excludePatterns
            "Some.Package", // dependencyName
            false, // expectMatch
        ];

        yield return
        [
            new[] { "*" }, // patterns
            new[] { "other.*" }, // excludePatterns
            "Some.Package", // dependencyName
            true, // expectMatch
        ];
    }

    [Theory]
    [MemberData(nameof(GetMatchingPullRequestTestData))]
    public void GetMatchingPullRequest(Job job, IEnumerable<Dependency> dependencies, bool considerVersions, string? expectedGroupPrName, string[]? expectedPrDependencyNames)
    {
        var existingPr = job.GetExistingPullRequestForDependencies(dependencies, considerVersions);

        if (expectedPrDependencyNames is null)
        {
            Assert.Null(existingPr);
            return;
        }
        else
        {
            Assert.NotNull(existingPr);
        }

        Assert.Equal(expectedGroupPrName, existingPr.Item1);

        var actualPrDependencyNames = existingPr.Item2
            .Select(d => d.DependencyName)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        AssertEx.Equal(expectedPrDependencyNames, actualPrDependencyNames);
    }

    public static IEnumerable<object?[]> GetMatchingPullRequestTestData()
    {
        var source = new JobSource()
        {
            Provider = "github",
            Repo = "test/repo",
        };

        // match found, version match
        yield return
        [
            // job
            new Job()
            {
                Source = source,
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Dependency.A",
                                DependencyVersion = NuGetVersion.Parse("1.0.0"),
                            },
                            new()
                            {
                                DependencyName = "Dependency.B",
                                DependencyVersion = NuGetVersion.Parse("2.0.0"),
                            }
                        ]
                    }
                ]
            },
            // dependencies
            new[]
            {
                new Dependency("Dependency.A", "1.0.0", DependencyType.Unknown),
                new Dependency("Dependency.B", "2.0.0", DependencyType.Unknown),
            },
            // considerVersions
            true,
            // expectedGroupPrName
            null,
            // expectedPrDependencyNames
            new[] { "Dependency.A", "Dependency.B" },
        ];

        // match found, version agnostic
        yield return
        [
            // job
            new Job()
            {
                Source = source,
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Dependency.A",
                                DependencyVersion = NuGetVersion.Parse("1.0.0"),
                            },
                            new()
                            {
                                DependencyName = "Dependency.B",
                                DependencyVersion = NuGetVersion.Parse("2.0.0"),
                            }
                        ]
                    }
                ]
            },
            // dependencies
            new[]
            {
                new Dependency("Dependency.A", "3.0.0", DependencyType.Unknown),
                new Dependency("Dependency.B", "4.0.0", DependencyType.Unknown),
            },
            // considerVersions
            false,
            // expectedGroupPrName
            null,
            // expectedPrDependencyNames
            new[] { "Dependency.A", "Dependency.B" },
        ];

        // match not found, version didn't match
        yield return
        [
            // job
            new Job()
            {
                Source = source,
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Dependency.A",
                                DependencyVersion = NuGetVersion.Parse("1.0.0"),
                            },
                            new()
                            {
                                DependencyName = "Dependency.B",
                                DependencyVersion = NuGetVersion.Parse("2.0.0"),
                            }
                        ]
                    }
                ]
            },
            // dependencies
            new[]
            {
                new Dependency("Dependency.A", "1.0.0", DependencyType.Unknown),
                new Dependency("Dependency.B", "3.0.0", DependencyType.Unknown),
            },
            // considerVersions
            true,
            // expectedGroupPrName
            null,
            // expectedPrDependencyNames
            null,
        ];

        // no match found, missing a dependency
        yield return
        [
            // job
            new Job()
            {
                Source = source,
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Dependency.A",
                                DependencyVersion = NuGetVersion.Parse("1.0.0"),
                            },
                            new()
                            {
                                DependencyName = "Dependency.B",
                                DependencyVersion = NuGetVersion.Parse("2.0.0"),
                            }
                        ]
                    }
                ]
            },
            // dependencies
            new[]
            {
                new Dependency("Dependency.A", "1.0.0", DependencyType.Unknown),
            },
            // considerVersions
            true,
            // expectedGroupPrName
            null,
            // expectedPrDependencyNames
            null,
        ];

        // no match found, extra dependency
        yield return
        [
            // job
            new Job()
            {
                Source = source,
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Dependency.A",
                                DependencyVersion = NuGetVersion.Parse("1.0.0"),
                            },
                            new()
                            {
                                DependencyName = "Dependency.B",
                                DependencyVersion = NuGetVersion.Parse("2.0.0"),
                            }
                        ]
                    }
                ]
            },
            // dependencies
            new[]
            {
                new Dependency("Dependency.A", "1.0.0", DependencyType.Unknown),
                new Dependency("Dependency.B", "2.0.0", DependencyType.Unknown),
                new Dependency("Dependency.C", "3.0.0", DependencyType.Unknown),
            },
            // considerVersions
            false,
            // expectedGroupPrName
            null,
            // expectedPrDependencyNames
            null,
        ];

        // match found with group
        yield return
        [
            // job
            new Job()
            {
                Source = source,
                ExistingGroupPullRequests = [
                    new()
                    {
                        DependencyGroupName = "test-group",
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Dependency.A",
                                DependencyVersion = NuGetVersion.Parse("1.0.0"),
                            },
                            new()
                            {
                                DependencyName = "Dependency.B",
                                DependencyVersion = NuGetVersion.Parse("2.0.0"),
                            }
                        ]
                    }
                ]
            },
            // dependencies
            new[]
            {
                new Dependency("Dependency.A", "1.0.0", DependencyType.Unknown),
                new Dependency("Dependency.B", "2.0.0", DependencyType.Unknown),
            },
            // considerVersions
            true,
            // expectedGroupPrName
            "test-group",
            // expectedPrDependencyNames
            new[] { "Dependency.A", "Dependency.B" },
        ];
    }

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
