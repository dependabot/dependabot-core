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
    [MemberData(nameof(IsDependencyIgnoredByNameOnlyTestData))]
    public void IsDependencyIgnoredByNameOnly(Condition[] ignoreConditions, string dependencyName, bool expectedIgnored)
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
        var actualIsIgnored = job.IsDependencyIgnoredByNameOnly(dependencyName);

        // assert
        Assert.Equal(expectedIgnored, actualIsIgnored);
    }

    public static IEnumerable<object[]> IsDependencyIgnoredByNameOnlyTestData()
    {
        // non-matching name
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
            // expectedIgnored
            false,
        ];

        // matching name, but has version requirement
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
            // expectedIgnored
            false,
        ];

        // wildcard matching name
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
            // expectedIgnored
            true,
        ];

        // matching name, but has update type restrictions
        yield return
        [
            // ignoreConditions
            new[]
            {
                new Condition()
                {
                    DependencyName = "Some.*",
                    UpdateTypes = [ConditionUpdateType.SemVerMajor],
                }
            },
            // dependencyName
            "Some.Dependency",
            // expectedIgnored
            false,
        ];

        // explicitly null update types
        yield return
        [
            // ignoreConditions
            new[]
            {
                new Condition()
                {
                    DependencyName = "Some.*",
                    UpdateTypes = null,
                }
            },
            // dependencyName
            "Some.Dependency",
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
    [MemberData(nameof(DependencyInfoFromJobData))]
    public void DependencyInfoFromJob(Job job, Dependency dependency, DependencyInfo expectedDependencyInfo)
    {
        var actualDependencyInfo = RunWorker.GetDependencyInfo(job, dependency);
        var expectedString = JsonSerializer.Serialize(expectedDependencyInfo, AnalyzeWorker.SerializerOptions);
        var actualString = JsonSerializer.Serialize(actualDependencyInfo, AnalyzeWorker.SerializerOptions);
        Assert.Equal(expectedString, actualString);
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
        var actualRepoRelativePath = RunWorker.EnsureCorrectFileCasing(candidatePath, tempDir.DirectoryPath, new TestLogger());
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

    public static IEnumerable<object[]> DependencyInfoFromJobData()
    {
        // with security advisory
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
                ],
                IgnoredUpdateTypes = [],
            }
        ];

        yield return
        [
            // job
            new Job()
            {
                Source = new()
                {
                    Provider = "github",
                    Repo = "some/repo",
                },
                IgnoreConditions = [
                    new Condition()
                    {
                        DependencyName = "Some.*",
                        UpdateTypes = [ConditionUpdateType.SemVerMajor],
                    },
                    new Condition()
                    {
                        DependencyName = "Unrelated.*",
                        UpdateTypes = [ConditionUpdateType.SemVerMinor],
                    },
                ],
            },
            // dependency
            new Dependency("Some.Dependency", "1.0.0", DependencyType.PackageReference),
            // expectedDependencyInfo
            new DependencyInfo()
            {
                Name = "Some.Dependency",
                Version = "1.0.0",
                IsVulnerable = false,
                IgnoredVersions = [],
                Vulnerabilities = [],
                IgnoredUpdateTypes = [ConditionUpdateType.SemVerMajor],
            }
        ];
    }
}
