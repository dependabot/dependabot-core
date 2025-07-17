using System.Collections.Immutable;

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
                <em>Sourced from <a href="https://dev.azure.com/Some.Organization/Some.Owner/_git/Some.Dependency/tags">Some.Dependency's releases</a>.</em>

                No release notes found for this version range.

                Commits viewable in <a href="https://dev.azure.com/Some.Organization/Some.Owner/_git/Some.Dependency/commits">compare view</a>.
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
                <em>Sourced from <a href="https://example-org.visualstudio.com/Some.Owner/_git/Some.Dependency/tags">Some.Dependency's releases</a>.</em>

                No release notes found for this version range.

                Commits viewable in <a href="https://example-org.visualstudio.com/Some.Owner/_git/Some.Dependency/commits">compare view</a>.
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
                <em>Sourced from <a href="https://github.com/Some.Owner/Some.Dependency/releases">Some.Dependency's releases</a>.</em>
                <h2>2.0.0</h2>

                * point 5
                * point 6

                <h2>1.0.1</h2>

                * point 3
                * point 4

                Commits viewable in <a href="https://github.com/Some.Owner/Some.Dependency/compare/1.0.0...2.0.0">compare view</a>.
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
                <em>Sourced from <a href="https://github.com/Some.Owner/Some.Dependency/releases">Some.Dependency's releases</a>.</em>

                No release notes found for this version range.

                Commits viewable in <a href="https://github.com/Some.Owner/Some.Dependency/commits">compare view</a>.
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
                <em>Sourced from <a href="https://github.com/Some.Owner/Some.Dependency/releases">Some.Dependency's releases</a>.</em>

                No release notes found for this version range.

                Commits viewable in <a href="https://github.com/Some.Owner/Some.Dependency/commits">compare view</a>.
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
                <em>Sourced from <a href="https://gitlab.com/Some.Owner/Some.Dependency/-/releases">Some.Dependency's releases</a>.</em>
                <h2>2.0.0</h2>

                * point 5
                * point 6

                <h2>1.0.1</h2>

                Commits viewable in <a href="https://gitlab.com/Some.Owner/Some.Dependency/-/compare/1.0.0...2.0.0">compare view</a>.
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
                <em>Sourced from <a href="https://gitlab.com/Some.Owner/Some.Dependency/-/releases">Some.Dependency's releases</a>.</em>

                No release notes found for this version range.

                Commits viewable in <a href="https://gitlab.com/Some.Owner/Some.Dependency/-/commits">compare view</a>.
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
                <em>Sourced from <a href="https://gitlab.com/Some.Owner/Some.Dependency/-/releases">Some.Dependency's releases</a>.</em>

                No release notes found for this version range.

                Commits viewable in <a href="https://gitlab.com/Some.Owner/Some.Dependency/-/commits">compare view</a>.
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

    private static async Task TestAsync(
        ImmutableArray<UpdateOperationBase> updateOperationsPerformed,
        ImmutableArray<ReportedDependency> updatedDependencies,
        (string Url, string Body)[] httpResponses,
        string expectedBody
    )
    {
        // arrange
        var job = new Job()
        {
            Source = new()
            {
                Provider = "github",
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
