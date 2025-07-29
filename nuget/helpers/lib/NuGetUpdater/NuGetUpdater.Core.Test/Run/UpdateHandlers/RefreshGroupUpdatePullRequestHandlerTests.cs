using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.UpdateHandlers;

public class RefreshGroupUpdatePullRequestHandlerTests : UpdateHandlersTestsBase
{
    [Fact]
    public async Task GeneratesUpdatePullRequest()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "test_group" }],
                DependencyGroupToRefresh = "test_group",
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                Source = CreateJobSource("/src"),
                UpdatingAPullRequest = true,
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
                                new("Unrelated.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
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
                    UpdateOperations = [new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/src/project.csproj"] }],
                };
            }),
            expectedUpdateHandler: RefreshGroupUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
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
                            Name = "Unrelated.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "update_version_group_pr",
                    }
                },
                new UpdatePullRequest()
                {
                    DependencyNames = ["Some.Dependency"],
                    DependencyGroup = "test_group",
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesUpdatePullRequest_FirstUpdateDidNothingSecondUpdateSucceeded()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "test_group" }],
                DependencyGroupToRefresh = "test_group",
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                Source = CreateJobSource("/src"),
                UpdatingAPullRequest = true,
            },
            files: [
                ("src/project1.csproj", "initial contents"),
                ("src/project2.csproj", "initial contents"),
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project1.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Unrelated.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "project2.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Unrelated.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
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

                ImmutableArray<UpdateOperationBase> updateOperations = [];
                if (workspacePath.EndsWith("project2.csproj"))
                {
                    // only report an update performed on the second project
                    updateOperations = [new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/src/project2.csproj"] }];
                    await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), "updated contents");
                }

                return new UpdateOperationResult()
                {
                    UpdateOperations = updateOperations,
                };
            }),
            expectedUpdateHandler: RefreshGroupUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project1.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Unrelated.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project1.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project2.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Unrelated.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project2.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project1.csproj", "/src/project2.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "update_version_group_pr",
                    }
                },
                new UpdatePullRequest()
                {
                    DependencyNames = ["Some.Dependency"],
                    DependencyGroup = "test_group",
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project2.csproj",
                            Content = "updated contents",
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesUpdatePullRequest_FirstDependencyNotAbleToUpdate()
    {
        var responseNumber = 0; // used to track which request was sent
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "test_group" }],
                DependencyGroupToRefresh = "test_group",
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                Source = CreateJobSource("/src"),
                UpdatingAPullRequest = true,
            },
            files: [
                ("src/project1.csproj", "initial contents"),
                ("src/project2.csproj", "initial contents"),
            ],
            discoveryWorker: TestDiscoveryWorker.FromResults(
                ("/src", new WorkspaceDiscoveryResult()
                {
                    Path = "/src",
                    Projects = [
                        new()
                        {
                            FilePath = "project1.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Unrelated.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "project2.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                                new("Unrelated.Dependency", "3.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        },
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

                AnalysisResult result = responseNumber == 0
                    ? new() { CanUpdate = false, UpdatedVersion = "1.0.0", UpdatedDependencies = [] }
                    : new() { CanUpdate = true, UpdatedVersion = "2.0.0", UpdatedDependencies = [] };
                responseNumber++;

                return Task.FromResult(result);
            }),
            updaterWorker: new TestUpdaterWorker(async input =>
            {
                var repoRoot = input.Item1;
                var workspacePath = input.Item2;
                var dependencyName = input.Item3;
                var previousVersion = input.Item4;
                var newVersion = input.Item5;
                var isTransitive = input.Item6;

                ImmutableArray<UpdateOperationBase> updateOperations = [];
                if (workspacePath.EndsWith("project2.csproj"))
                {
                    // only report an update performed on the second project
                    updateOperations = [new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/src/project2.csproj"] }];
                    await File.WriteAllTextAsync(Path.Join(repoRoot, workspacePath), "updated contents");
                }

                return new UpdateOperationResult()
                {
                    UpdateOperations = updateOperations,
                };
            }),
            expectedUpdateHandler: RefreshGroupUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project1.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Unrelated.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project1.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project2.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Unrelated.Dependency",
                            Version = "3.0.0",
                            Requirements = [
                                new() { Requirement = "3.0.0", File = "/src/project2.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/project1.csproj", "/src/project2.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "update_version_group_pr",
                    }
                },
                new UpdatePullRequest()
                {
                    DependencyNames = ["Some.Dependency"],
                    DependencyGroup = "test_group",
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project2.csproj",
                            Content = "updated contents",
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesClosePullRequest_UpdateNoLongerPossible()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "test_group" }],
                DependencyGroupToRefresh = "test_group",
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                Source = CreateJobSource("/src"),
                UpdatingAPullRequest = true,
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
                    CanUpdate = false,
                    UpdatedVersion = "1.0.0",
                    UpdatedDependencies = [],
                });
            }),
            updaterWorker: new TestUpdaterWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: RefreshGroupUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
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
                        }
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "update_version_group_pr",
                    }
                },
                new ClosePullRequest() { DependencyNames = ["Some.Dependency"], Reason = "update_no_longer_possible" },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task RecreatesPullRequest()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency", "Some.Other.Dependency"],
                DependencyGroups = [new() { Name = "test_group" }],
                DependencyGroupToRefresh = "test_group",
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") },
                            new() { DependencyName = "Some.Other.Dependency", DependencyVersion = NuGetVersion.Parse("4.0.0") },
                        ]
                    },
                ],
                Source = CreateJobSource("/src"),
                UpdatingAPullRequest = true,
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
                var updatedVersion = dependencyInfo.Name switch
                {
                    "Some.Dependency" => "2.0.1",
                    "Some.Other.Dependency" => "4.0.1",
                    _ => throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}"),
                };

                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = updatedVersion,
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
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = ["/src/project.csproj"] }],
                };
            }),
            expectedUpdateHandler: RefreshGroupUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
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
                        }
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "update_version_group_pr",
                    }
                },
                new ClosePullRequest() { DependencyNames = ["Some.Dependency", "Some.Other.Dependency"], Reason = "dependencies_changed" },
                new CreatePullRequest()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "2.0.1",
                            Requirements = [
                                new() { Requirement = "2.0.1", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        },
                        new()
                        {
                            Name = "Some.Other.Dependency",
                            Version = "4.0.1",
                            Requirements = [
                                new() { Requirement = "4.0.1", File = "/src/project.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "3.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "3.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
                            ],
                        }
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = "test_group",
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesCreatePullRequest()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                DependencyGroups = [new() { Name = "test_group" }],
                DependencyGroupToRefresh = "test_group",
                ExistingPullRequests = [
                    new()
                    {
                        Dependencies = [
                            new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") },
                            new() { DependencyName = "Some.Other.Dependency", DependencyVersion = NuGetVersion.Parse("4.0.0") },
                        ]
                    },
                ],
                Source = CreateJobSource("/src"),
                UpdatingAPullRequest = true,
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
                var updatedVersion = dependencyInfo.Name switch
                {
                    "Some.Dependency" => "2.0.0",
                    _ => throw new NotImplementedException($"Test didn't expect to update dependency {dependencyInfo.Name}"),
                };

                return Task.FromResult(new AnalysisResult()
                {
                    CanUpdate = true,
                    UpdatedVersion = updatedVersion,
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
                    UpdateOperations = [new DirectUpdate() { DependencyName = dependencyName, NewVersion = NuGetVersion.Parse(newVersion), UpdatedFiles = ["/src/project.csproj"] }],
                };
            }),
            expectedUpdateHandler: RefreshGroupUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
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
                        }
                    ],
                    DependencyFiles = ["/src/project.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "update_version_group_pr",
                    }
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
                        }
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = EndToEndTests.TestPullRequestCommitMessage,
                    PrTitle = EndToEndTests.TestPullRequestTitle,
                    PrBody = EndToEndTests.TestPullRequestBody,
                    DependencyGroup = "test_group",
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }
}
