using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.UpdateHandlers;

public class RefreshSecurityUpdatePullRequestHandlerTests : UpdateHandlersTestsBase
{
    [Fact]
    public async Task GeneratesUpdatePullRequest()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
                SecurityUpdatesOnly = true,
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
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "update_security_pr",
                    }
                },
                new UpdatePullRequest()
                {
                    DependencyNames = ["Some.Dependency"],
                    DependencyGroup = null,
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "project.csproj",
                            Content = "updated contents",
                        }
                    ],
                    BaseCommitSha = "TEST-COMMIT-SHA",
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesClosePullRequest_DependenciesRemoved()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
                SecurityUpdatesOnly = true,
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
                                new("Unrelated.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Unrelated.Dependency",
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
                        ["operation"] = "update_security_pr",
                    }
                },
                new ClosePullRequest() { DependencyNames = ["Some.Dependency"], Reason = "dependencies_removed" },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesClosePullRequest_DependencyRemoved()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency", "Other.Dependency"],
                ExistingPullRequests = [
                    new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] },
                    new() { Dependencies = [new() { DependencyName = "Other.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] },
                ],
                SecurityAdvisories = [
                    new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] },
                    new() { DependencyName = "Other.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] },
                ],
                SecurityUpdatesOnly = true,
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
            analyzeWorker: new TestAnalyzeWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "update_security_pr",
                    }
                },
                new ClosePullRequest() { DependencyNames = ["Other.Dependency"], Reason = "dependency_removed" },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesClosePullRequest_UpToDate()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")], PatchedVersions = [Requirement.Parse("2.0.0")] }],
                SecurityUpdatesOnly = true,
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
                                new("Some.Dependency", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(input => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
            expectedApiMessages: [
                new UpdatedDependencyList()
                {
                    Dependencies = [
                        new()
                        {
                            Name = "Some.Dependency",
                            Version = "2.0.0",
                            Requirements = [
                                new() { Requirement = "2.0.0", File = "/src/project.csproj", Groups = ["dependencies"] },
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
                        ["operation"] = "update_security_pr",
                    }
                },
                new ClosePullRequest() { DependencyNames = ["Some.Dependency"], Reason = "up_to_date" },
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
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
                SecurityUpdatesOnly = true,
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
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "update_security_pr",
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
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
                SecurityUpdatesOnly = true,
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
                    CanUpdate = true,
                    UpdatedVersion = "2.0.1",
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
                    UpdateOperations = [new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.1"), UpdatedFiles = ["/src/project.csproj"] }],
                };
            }),
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "update_security_pr",
                    }
                },
                new ClosePullRequest() { DependencyNames = ["Some.Dependency"], Reason = "dependencies_changed" },
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
    public async Task GeneratesCreatePullRequest()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Unrelated.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
                SecurityUpdatesOnly = true,
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
            expectedUpdateHandler: RefreshSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "update_security_pr",
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
                    CommitMessage = RunWorkerTests.TestPullRequestCommitMessage,
                    PrTitle = RunWorkerTests.TestPullRequestTitle,
                    PrBody = RunWorkerTests.TestPullRequestBody,
                    DependencyGroup = null,
                },
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }
}
