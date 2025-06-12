using System.Collections.Immutable;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.UpdateHandlers;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.UpdateHandlers;

public class CreateSecurityUpdatePullRequestHandlerTests : UpdateHandlersTestsBase
{
    [Fact]
    public async Task GeneratesCreatePullRequest()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
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

    [Fact]
    public async Task GeneratesCreatePullRequest_UpdatingOneProjectImplicitlyUpdatesTheOther()
    {
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
                SecurityUpdatesOnly = true,
                Source = CreateJobSource("/src"),
            },
            files: [
                ("src/Directory.Packages.props", "initial contents"),
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
                            ],
                            ImportedFiles = ["Directory.Packages.props"],
                            AdditionalFiles = [],
                        },
                        new()
                        {
                            FilePath = "project2.csproj",
                            Dependencies = [
                                new("Some.Dependency", "1.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = ["Directory.Packages.props"],
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

                await File.WriteAllTextAsync(Path.Join(repoRoot, "src/Directory.Packages.props"), "updated contents");

                // only report an update performed on the first project
                ImmutableArray<UpdateOperationBase> updateOperations = workspacePath.EndsWith("project1.csproj")
                    ? [new DirectUpdate() { DependencyName = "Some.Dependency", NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = ["/src/Directory.Packages.csproj"] }]
                    : [];

                return new UpdateOperationResult()
                {
                    UpdateOperations = updateOperations,
                };
            }),
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                            Name = "Some.Dependency",
                            Version = "1.0.0",
                            Requirements = [
                                new() { Requirement = "1.0.0", File = "/src/project2.csproj", Groups = ["dependencies"] },
                            ],
                        },
                    ],
                    DependencyFiles = ["/src/Directory.Packages.props", "/src/project1.csproj", "/src/project2.csproj"],
                },
                new IncrementMetric()
                {
                    Metric = "updater.started",
                    Tags = new()
                    {
                        ["operation"] = "create_security_pr",
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
                                new() { Requirement = "2.0.0", File = "/src/project1.csproj", Groups = ["dependencies"], Source = new() { SourceUrl = null } },
                            ],
                            PreviousVersion = "1.0.0",
                            PreviousRequirements = [
                                new() { Requirement = "1.0.0", File = "/src/project1.csproj", Groups = ["dependencies"] },
                            ],
                        }
                    ],
                    UpdatedDependencyFiles = [
                        new()
                        {
                            Directory = "/src",
                            Name = "Directory.Packages.props",
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
    public async Task GeneratesSecurityUpdateDependencyNotFound()
    {
        // requested dependency doesn't exist
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["This.Dependency.Does.Not.Exist"],
                SecurityAdvisories = [new() { DependencyName = "This.Dependency.Does.Not.Exist", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(_ => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(_ => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
                    }
                },
                new SecurityUpdateDependencyNotFound(),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesSecurityUpdateNotNeeded()
    {
        // requested dependency exists, but isn't vulnerable
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
                                new("Some.Dependency", "2.0.0", DependencyType.PackageReference, TargetFrameworks: ["net9.0"]),
                            ],
                            ImportedFiles = [],
                            AdditionalFiles = [],
                        }
                    ],
                })
            ),
            analyzeWorker: new TestAnalyzeWorker(_ => throw new NotImplementedException("test shouldn't get this far")),
            updaterWorker: new TestUpdaterWorker(_ => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
                    }
                },
                new SecurityUpdateNotNeeded("Some.Dependency"),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesSecurityUpdateNotFound()
    {
        // dependency exists and is vulnerable, but non-vulnerable version isn't on feed
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
            updaterWorker: new TestUpdaterWorker(_ => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
                    }
                },
                new SecurityUpdateNotFound("Some.Dependency", "1.0.0"),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesSecurityUpdateIgnored()
    {
        // vulnerable dependency exists, but it is explicitly ignored
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                IgnoreConditions = [new() { DependencyName = "Some.Dependency" }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
            updaterWorker: new TestUpdaterWorker(_ => throw new NotImplementedException("test shouldn't get this far")),
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
                    }
                },
                new SecurityUpdateIgnored("Some.Dependency"),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesSecurityUpdateNotPossible()
    {
        // vulnerable dependency exists and update was attempted, but nothing could be done
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
            updaterWorker: new TestUpdaterWorker(input =>
            {
                return Task.FromResult(new UpdateOperationResult()
                {
                    UpdateOperations = [], // nothing could be done
                });
            }),
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
                    }
                },
                new SecurityUpdateNotPossible("Some.Dependency", "2.0.0", "2.0.0", []),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }

    [Fact]
    public async Task GeneratesPullRequestExistsForSecurityUpdate()
    {
        // everything was successful, but a PR already exists
        await TestAsync(
            job: new Job()
            {
                Dependencies = ["Some.Dependency"],
                ExistingPullRequests = [new() { Dependencies = [new() { DependencyName = "Some.Dependency", DependencyVersion = NuGetVersion.Parse("2.0.0") }] }],
                SecurityAdvisories = [new() { DependencyName = "Some.Dependency", AffectedVersions = [Requirement.Parse("= 1.0.0")] }],
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
            expectedUpdateHandler: CreateSecurityUpdatePullRequestHandler.Instance,
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
                        ["operation"] = "create_security_pr",
                    }
                },
                new PullRequestExistsForSecurityUpdate([new("Some.Dependency", "2.0.0", DependencyType.Unknown)]),
                new MarkAsProcessed("TEST-COMMIT-SHA"),
            ]
        );
    }
}
