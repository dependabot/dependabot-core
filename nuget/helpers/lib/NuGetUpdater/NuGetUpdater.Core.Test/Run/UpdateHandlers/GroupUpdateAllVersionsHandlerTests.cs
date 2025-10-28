using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Test.Utilities;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.UpdateHandlers;

public class GroupUpdateAllVersionsHandlerTests : UpdateHandlersTestsBase
{
    [Fact]
    public void UpdatesAreCollectedByDependencyNameAndVersion()
    {
        var discovery = new WorkspaceDiscoveryResult()
        {
            Path = "/",
            Projects = [
                new()
                {
                    FilePath = "project1.csproj",
                    Dependencies = [new("SOME.DEPENDENCY", "1.0.0", DependencyType.PackageReference, IsTransitive: true)],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                new()
                {
                    FilePath = "project2.csproj",
                    Dependencies = [new("some.dependency", "1.0.0", DependencyType.PackageReference, IsTransitive: false)],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ]
        };
        var updateOperations = GroupUpdateAllVersionsHandler.CollectUpdateOperationsByDependency(discovery);
        var updateOperation = Assert.Single(updateOperations);
        Assert.Equal("some.dependency/1.0.0", updateOperation.Key.ToString());
        var operationProjects = updateOperation.Select(p => p.ProjectPath).ToArray();
        AssertEx.Equal(["/project1.csproj", "/project2.csproj"], operationProjects);
    }

    [Fact]
    public async Task GeneratesCreatePullRequest_NoGroups()
    {
        // no groups specified; create 1 PR for each directory for each dependency
        await TestAsync(
            job: new Job()
            {
                Source = CreateJobSource("/src", "/test"),
            },
            files: [
                ("src/project.csproj", "initial contents"),
                ("test/project.csproj", "initial contents"),
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Production.Dependency.1", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Production.Dependency.2", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                }),
                ("/test", new WorkspaceDiscoveryResult()
                {
                    Path = "/test",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Test.Dependency", "5.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var repoRoot = input.Item1;
                var discovery = input.Item2;
                var dependencyInfo = input.Item3;
                var newVersion = dependencyInfo.Name switch
                {
                    "Production.Dependency.1" => "2.0.0",
                    "Production.Dependency.2" => "4.0.0",
                    "Test.Dependency" => "6.0.0",
                    _ => throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}"),
                };
                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = newVersion,
                    UpdatedDependencies = [],
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRoot = input.Item1;
                var workspacePath = input.Item2;
                var dependencyName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var isTransitive = input.Item6;

                await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), "updated contents");

                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = [workspacePath] }],
                };
            }),
            expectedUpdateHandler: GroupUpdateAllVersionsHandler.Instance,
            expectedApiMessages: [
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions",
                    }
                },
                // for "/src"
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Production.Dependency.1",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Production.Dependency.2",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                // for "/src" and Production.Dependency.1
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Production.Dependency.1",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                // for "/src" and Production.Dependency.2
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Production.Dependency.2",
                            Version = "4.0.0",
                            Requirements = [
                                new() { Requirement = "4.0.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "3.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                // for "/test"
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Test.Dependency",
                            Version = "5.0.0",
                            Requirements = [
                                new() { Requirement = "5.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/test/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Test.Dependency",
                            Version = "6.0.0",
                            Requirements = [
                                new() { Requirement = "6.0.0", File = "/test/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "5.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "5.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/test",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesCreatePullRequest_GroupedAndUngrouped()
    {
        // single groups specified; creates 1 PR for both directories
        await TestAsync(
            job: new Job()
            {
                Source = CreateJobSource("/src", "/test"),
                DependencyGroups = [
                    new()
                    {
                        Name = "test-group",
                        Rules = new()
                        {
                            ["patterns"] = new[] { "*" },
                            ["exclude-patterns"] = new[] { "Ungrouped.*" },
                        },
                    },
                ],
            },
            files: [
                ("src/project.csproj", "initial contents"),
                ("test/project.csproj", "initial contents"),
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Some.Other.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Ungrouped.Dependency", "5.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                }),
                ("/test", new WorkspaceDiscoveryResult()
                {
                    Path = "/test",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Some.Other.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Ungrouped.Dependency", "5.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var repoRoot = input.Item1;
                var discovery = input.Item2;
                var dependencyInfo = input.Item3;
                var newVersion = dependencyInfo.Name switch
                {
                    "Some.Dependency" => "2.0.0",
                    "Some.Other.Dependency" => "4.0.0",
                    "Ungrouped.Dependency" => "6.0.0",
                    _ => throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}"),
                };
                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = newVersion,
                    UpdatedDependencies = [],
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRoot = input.Item1;
                var workspacePath = input.Item2;
                var dependencyName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var isTransitive = input.Item6;

                await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), "updated contents");

                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = [workspacePath] }],
                };
            }),
            expectedUpdateHandler: GroupUpdateAllVersionsHandler.Instance,
            expectedApiMessages: [
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions",
                    }
                },
                // first the grouped updates
                // for "/src"
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Ungrouped.Dependency",
                            Version = "5.0.0",
                            Requirements = [
                                new() { Requirement = "5.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                // for "/test"
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Ungrouped.Dependency",
                            Version = "5.0.0",
                            Requirements = [
                                new() { Requirement = "5.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/test/project.csproj"],
                },
                // for both directories
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "4.0.0",
                            Requirements = [
                                new() { Requirement = "4.0.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "3.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/test/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "4.0.0",
                            Requirements = [
                                new() { Requirement = "4.0.0", File = "/test/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "3.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "3.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                        new()
                        {
                            Directory = "/test",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = "test-group",
                },
                // now the ungrouped updates
                // for "/src"
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Ungrouped.Dependency",
                            Version = "5.0.0",
                            Requirements = [
                                new() { Requirement = "5.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Ungrouped.Dependency",
                            Version = "6.0.0",
                            Requirements = [
                                new() { Requirement = "6.0.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "5.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "5.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                // for "/test"
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Ungrouped.Dependency",
                            Version = "5.0.0",
                            Requirements = [
                                new() { Requirement = "5.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/test/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Ungrouped.Dependency",
                            Version = "6.0.0",
                            Requirements = [
                                new() { Requirement = "6.0.0", File = "/test/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "5.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "5.0.0", File = "/test/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/test",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesCreatePullRequest_Grouped_SecurityUpdatesOnly()
    {
        // no groups specified; create 1 PR for each directory, but only for those dependencies explicitly listed
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [
                    new()
                    {
                        Name = "test-group",
                        Rules = new()
                        {
                            ["patterns"] = new[] { "*" }
                        },
                        AppliesTo = "security-updates",
                    }
                ],
                SecurityAdvisories = [
                    new()
                    {
                        DependencyName = "Some.Dependency",
                        PatchedVersions = [],
                        UnaffectedVersions = [],
                        AffectedVersions = [Requirement.Parse("< 2.0.0")]
                    }
                ],
                SecurityUpdatesOnly = true,
                Source = CreateJobSource("/src"),
            },
            files: [
                ("src/project.csproj", "initial contents"),
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Some.Other.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var repoRoot = input.Item1;
                var discovery = input.Item2;
                var dependencyInfo = input.Item3;
                if (dependencyInfo.Name != "Some.Dependency")
                {
                    throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}");
                }

                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = "2.0.0",
                    UpdatedDependencies = [],
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRoot = input.Item1;
                var workspacePath = input.Item2;
                var dependencyName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var isTransitive = input.Item6;

                await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), "updated contents");

                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = [workspacePath] }],
                };
            }),
            expectedUpdateHandler: GroupUpdateAllVersionsHandler.Instance,
            expectedApiMessages: [
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions",
                    }
                },
                // grouped check
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = "test-group",
                },
                // ungrouped check
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesCreatePullRequest_Grouped_ExistingPrSkipped()
    {
        // two groups specified, but one has existing PR and is skipped
        await TestAsync(
            job: new Job()
            {
                Source = CreateJobSource("/src"),
                DependencyGroups = [
                    new()
                    {
                        Name = "test-group-1",
                        Rules = new()
                        {
                            ["patterns"] = new[] { "Package.For.Group.One" },
                        },
                    },
                    new()
                    {
                        Name = "test-group-2", // this group has an existing PR and will be skipped
                        Rules = new()
                        {
                            ["patterns"] = new[] { "Package.For.Group.Two" },
                        },
                    },
                ],
                ExistingGroupPullRequests = [
                    new()
                    {
                        DependencyGroupName = "test-group-2",
                        Dependencies = [
                            new()
                            {
                                DependencyName = "Package.For.Group.Two",
                                DependencyVersion = NuGetVersion.Parse("2.0.1"),
                            }
                        ]
                    }
                ]
            },
            files: [
                ("src/project.csproj", "initial contents"),
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Package.For.Group.One", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Package.For.Group.Two", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var repoRoot = input.Item1;
                var discovery = input.Item2;
                var dependencyInfo = input.Item3;
                var newVersion = dependencyInfo.Name switch
                {
                    "Package.For.Group.One" => "1.0.1",
                    "Package.For.Group.Two" => "2.0.1",
                    _ => throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}"),
                };
                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = newVersion,
                    UpdatedDependencies = [],
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRoot = input.Item1;
                var workspacePath = input.Item2;
                var dependencyName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var isTransitive = input.Item6;

                await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), $"updated contents for {dependencyName}/{newVersion}");

                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = [workspacePath] }],
                };
            }),
            expectedUpdateHandler: GroupUpdateAllVersionsHandler.Instance,
            expectedApiMessages: [
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions",
                    }
                },
                // grouped check
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.For.Group.One",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Package.For.Group.Two",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.For.Group.One",
                            Version = "1.0.1",
                            Requirements = [
                                new() { Requirement = "1.0.1", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents for Package.For.Group.One/1.0.1",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = "test-group-1",
                },
                // ungrouped check
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Package.For.Group.One",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Package.For.Group.Two",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task IgnoredVersionUpdateTypesAreHonored()
    {
        await TestAsync(
            job: new()
            {
                Source = CreateJobSource("/src"),
                IgnoreConditions = [
                    new Condition()
                    {
                        DependencyName = "Some.Dependency",
                        UpdateTypes = [ConditionUpdateType.SemVerMajor],
                    }
                ]
            },
            files: [("src/project.csproj", "initial contents")],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input =>
            {
                var repoRoot = input.Item1;
                var discovery = input.Item2;
                var dependencyInfo = input.Item3;
                if (dependencyInfo.IgnoredUpdateTypes.Length != 1 || !dependencyInfo.IgnoredUpdateTypes.Contains(ConditionUpdateType.SemVerMajor))
                {
                    throw new InvalidOperationException($"Expected to see ignored update type of {nameof(ConditionUpdateType.SemVerMajor)} but found [{string.Join(", ", dependencyInfo.IgnoredUpdateTypes)}]");
                }
                var newVersion = dependencyInfo.Name switch
                {
                    "Some.Dependency" => "1.1.0",
                    _ => throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}"),
                };
                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = newVersion,
                    UpdatedDependencies = [],
                });
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRoot = input.Item1;
                var workspacePath = input.Item2;
                var dependencyName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var isTransitive = input.Item6;

                await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), "updated contents");

                return new UpdateOperationResult()
                {
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = [workspacePath] }],
                };
            }),
            expectedUpdateHandler: GroupUpdateAllVersionsHandler.Instance,
            expectedApiMessages: [
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "group_update_all_versions",
                    }
                },
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.1.0",
                            Requirements = [
                                new() { Requirement = "1.1.0", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }
}
