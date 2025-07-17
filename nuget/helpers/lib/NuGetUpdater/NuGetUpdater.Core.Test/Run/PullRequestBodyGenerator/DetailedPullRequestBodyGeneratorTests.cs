using System.Collections.Immutable;
using System.Text;

using NuGet.Versioning;

using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Run.PullRequestBodyGenerator;
using NuGetUpdater.Core.Updater;

using Xunit;

namespace NuGetUpdater.Core.Test.Run.PullRequestBodyGenerator;

public class DetailedPullRequestBodyGeneratorTests
{
    [Fact]
    public async Task GeneratePrBody_Azure()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://dev.azure.com/Some.Organization/Some.Owner/_git/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated [Some.Dependency](https://dev.azure.com/Some.Organization/Some.Owner/_git/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://dev.azure.com/Some.Organization/Some.Owner/_git/Some.Dependency/tags)._

                No release notes found for this version range.

                Commits viewable in [compare view](https://dev.azure.com/Some.Organization/Some.Owner/_git/Some.Dependency/commits).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_Azure_VisualStudioDomain()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://example-org.visualstudio.com/Some.Owner/_git/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated [Some.Dependency](https://example-org.visualstudio.com/Some.Owner/_git/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://example-org.visualstudio.com/Some.Owner/_git/Some.Dependency/tags)._

                No release notes found for this version range.

                Commits viewable in [compare view](https://example-org.visualstudio.com/Some.Owner/_git/Some.Dependency/commits).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_GitHub()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://github.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [
                ("https://api.github.com/repos/Some.Owner/Some.Dependency/releases?per_page=100", """
                    [
                      {
                        "name": "2.0.0",
                        "tag_name": "2.0.0",
                        "body": "* point 5\n* point 6"
                      },
                      {
                        "name": "1.0.1",
                        "tag_name": "1.0.1",
                        "body": "* point 3\n* point 4"
                      },
                      {
                        "name": "1.0.0",
                        "tag_name": "1.0.0",
                        "body": "* point 1\n* point 2"
                      }
                    ]
                    """)
            ],
            expectedBody: """
                Updated [Some.Dependency](https://github.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://github.com/Some.Owner/Some.Dependency/releases)._

                ## 2.0.0

                * point 5
                * point 6

                ## 1.0.1

                * point 3
                * point 4

                Commits viewable in [compare view](https://github.com/Some.Owner/Some.Dependency/compare/1.0.0...2.0.0).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_GitHub_EmptyApiResponses()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://github.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated [Some.Dependency](https://github.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://github.com/Some.Owner/Some.Dependency/releases)._

                No release notes found for this version range.

                Commits viewable in [compare view](https://github.com/Some.Owner/Some.Dependency/commits).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_GitHub_NonJsonResponse()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://github.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [
                ("https://api.github.com/repos/Some.Owner/Some.Dependency/releases?per_page=100", """
                    this is not JSON
                    """)
            ],
            expectedBody: """
                Updated [Some.Dependency](https://github.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://github.com/Some.Owner/Some.Dependency/releases)._

                No release notes found for this version range.

                Commits viewable in [compare view](https://github.com/Some.Owner/Some.Dependency/commits).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_GitLab()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://gitlab.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [
                ("https://gitlab.com/api/v4/projects/Some.Owner%2FSome.Dependency/repository/tags", """
                    [
                      {
                        "name": "2.0.0",
                        "release": {
                          "tag_name": "2.0.0",
                          "description": "* point 5\n* point 6"
                        }
                      },
                      {
                        "name": "1.0.1",
                        "release": null
                      },
                      {
                        "name": "1.0.0",
                        "release": null
                      }
                    ]
                    """)
            ],
            expectedBody: """
                Updated [Some.Dependency](https://gitlab.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://gitlab.com/Some.Owner/Some.Dependency/-/releases)._

                ## 2.0.0

                * point 5
                * point 6

                ## 1.0.1

                Commits viewable in [compare view](https://gitlab.com/Some.Owner/Some.Dependency/-/compare/1.0.0...2.0.0).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_GitLab_EmptyApiResponses()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://gitlab.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated [Some.Dependency](https://gitlab.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://gitlab.com/Some.Owner/Some.Dependency/-/releases)._

                No release notes found for this version range.

                Commits viewable in [compare view](https://gitlab.com/Some.Owner/Some.Dependency/-/commits).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_GitLab_NonJsonResponse()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://gitlab.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [
                ("https://gitlab.com/api/v4/projects/Some.Owner%2FSome.Dependency/repository/tags", """
                    this is not JSON
                    """)
            ],
            expectedBody: """
                Updated [Some.Dependency](https://gitlab.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                <details>
                <summary>Release notes</summary>

                _Sourced from [Some.Dependency's releases](https://gitlab.com/Some.Owner/Some.Dependency/-/releases)._

                No release notes found for this version range.

                Commits viewable in [compare view](https://gitlab.com/Some.Owner/Some.Dependency/-/commits).
                </details>
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_NoSource()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated Some.Dependency from 1.0.0 to 2.0.0.
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_NoSource_DuplicateUpdateOperations()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated Some.Dependency from 1.0.0 to 2.0.0.
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_NoSource_MultipleUpdates()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
                new DirectUpdate() { DependencyName = "Other.Dependency", OldVersion = NuGetVersion.Parse("3.0.0"), NewVersion = NuGetVersion.Parse("4.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                        }
                    ],
                },
                new ReportedDependency()
                {
                    Name = "Other.Dependency",
                    PreviousVersion = "3.0.0",
                    Version = "4.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "4.0.0",
                        }
                    ],
                },
            ],
            httpResponses: [],
            expectedBody: """
                Updated Other.Dependency from 3.0.0 to 4.0.0.

                Updated Some.Dependency from 1.0.0 to 2.0.0.
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_UnsupportedSource()
    {
        await TestAsync(
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://example.com/git/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [],
            expectedBody: """
                Updated [Some.Dependency](https://example.com/git/Some.Dependency) from 1.0.0 to 2.0.0.
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_NoHtmlIfNotSupported()
    {
        // PR will be pushed to a repo that doesn't support HTML in the PR body
        await TestAsync(
            sourceProvider: "azure",
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://github.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [
                ("https://api.github.com/repos/Some.Owner/Some.Dependency/releases?per_page=100", """
                    [
                      {
                        "name": "2.0.0",
                        "tag_name": "2.0.0",
                        "body": "* point 5\n* point 6"
                      },
                      {
                        "name": "1.0.1",
                        "tag_name": "1.0.1",
                        "body": "* point 3\n* point 4"
                      },
                      {
                        "name": "1.0.0",
                        "tag_name": "1.0.0",
                        "body": "* point 1\n* point 2"
                      }
                    ]
                    """)
            ],
            expectedBody: """
                Updated [Some.Dependency](https://github.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                # Release notes

                _Sourced from [Some.Dependency's releases](https://github.com/Some.Owner/Some.Dependency/releases)._

                ## 2.0.0

                * point 5
                * point 6

                ## 1.0.1

                * point 3
                * point 4

                Commits viewable in [compare view](https://github.com/Some.Owner/Some.Dependency/compare/1.0.0...2.0.0).
                """
        );
    }

    [Fact]
    public async Task GeneratePrBody_ReleaseNotesAreTruncated()
    {
        // individual release notes are truncated by lines
        var longReleaseNote = new StringBuilder();
        for (int i = 1; i <= 60; i++)
        {
            longReleaseNote.AppendLine($"* line {i}");
        }

        // only generating 49 lines so we can manually verify the 50th
        var expectedReleaseNote = new StringBuilder();
        for (int i = 1; i <= 49; i++)
        {
            expectedReleaseNote.AppendLine($"* line {i}");
        }

        await TestAsync(
            sourceProvider: "azure",
            updateOperationsPerformed: [
                new DirectUpdate() { DependencyName = "Some.Dependency", OldVersion = NuGetVersion.Parse("1.0.0"), NewVersion = NuGetVersion.Parse("2.0.0"), UpdatedFiles = [] },
            ],
            updatedDependencies: [
                new ReportedDependency()
                {
                    Name = "Some.Dependency",
                    PreviousVersion = "1.0.0",
                    Version = "2.0.0",
                    Requirements = [
                        new ReportedRequirement()
                        {
                            File = "",
                            Requirement = "2.0.0",
                            Source = new()
                            {
                                SourceUrl = "https://github.com/Some.Owner/Some.Dependency",
                            },
                        }
                    ],
                }
            ],
            httpResponses: [
                ("https://api.github.com/repos/Some.Owner/Some.Dependency/releases?per_page=100", $$"""
                    [
                      {
                        "name": "2.0.0",
                        "tag_name": "2.0.0",
                        "body": "{{longReleaseNote.ToString().Replace("\r", "").Trim().Replace("\n", "\\n")}}"
                      },
                      {
                        "name": "1.0.0",
                        "tag_name": "1.0.0",
                        "body": "* line 1\n* line 2"
                      }
                    ]
                    """)
            ],
            expectedBody: $"""
                Updated [Some.Dependency](https://github.com/Some.Owner/Some.Dependency) from 1.0.0 to 2.0.0.

                # Release notes

                _Sourced from [Some.Dependency's releases](https://github.com/Some.Owner/Some.Dependency/releases)._

                ## 2.0.0

                {expectedReleaseNote.ToString().Replace("\r", "").Trim()}
                * line 50
                 ... (truncated)

                Commits viewable in [compare view](https://github.com/Some.Owner/Some.Dependency/compare/1.0.0...2.0.0).
                """
        );
    }

    private static async Task TestAsync(
        ImmutableArray<UpdateOperationBase> updateOperationsPerformed,
        ImmutableArray<ReportedDependency> updatedDependencies,
        (string Url, string Body)[] httpResponses,
        string expectedBody,
        string sourceProvider = "github"
    )
    {
        // arrange
        var job = new Job()
        {
            Source = new()
            {
                Provider = sourceProvider,
                Repo = "test/repo",
            }
        };

        // act
        var responses = httpResponses.ToDictionary(x => x.Url, x => x.Body);
        var httpFetcher = new TestHttpFetcher(responses);
        var generator = new DetailedPullRequestBodyGenerator(httpFetcher);
        var actualBody = await generator.GeneratePullRequestBodyTextAsync(job, updateOperationsPerformed, updatedDependencies);

        // assert
        Assert.Equal(expectedBody.Replace("\r", ""), actualBody.Replace("\r", ""));
    }
}
