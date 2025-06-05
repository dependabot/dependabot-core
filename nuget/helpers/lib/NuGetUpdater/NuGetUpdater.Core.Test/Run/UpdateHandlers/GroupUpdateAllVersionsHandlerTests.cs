using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.UpdateHandlers;

public class GroupUpdateAllVersionsHandlerTests : UpdateHandlersTestsBase
{
    [Fact]
    public async Task GeneratesCreatePullRequest_NoGroups()
    {
        // no groups specified; create 1 PR for each directory
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
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Some.Other.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
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
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody,
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
                    ],
                    DependencyFiles = ["/test/project.csproj"],
                },
                new CreatePullRequest()
                {
                    Dependencies = [
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
                            Directory = "/test",
                            Name = "project.csproj",
                            Content = "updated contents",
                        },
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesCreatePullRequest_Grouped()
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
                            ["exclude-patterns"] = new[] { "Unrelated.*" },
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
                                new("Unrelated.Dependency", "5.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
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
                                new("Unrelated.Dependency", "5.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
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
                            Name = "Unrelated.Dependency",
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
                            Name = "Unrelated.Dependency",
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
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody,
                    DependencyGroup = "test-group",
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
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody,
                    DependencyGroup = "test-group",
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }
}
