using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Graph;
using NuGetUpdater.Core.Run.ApiModel;

using Xunit;

namespace NuGetUpdater.Core.Test.Graph;

public class GraphWorkerTests
{
    [Theory]
    [MemberData(nameof(BuildDependencySubmissionTestData))]
    public void BuildDependencySubmission_ConvertsDiscoveryResults(
        WorkspaceDiscoveryResult discoveryResult,
        Job job,
        string baseCommitSha,
        string repoRoot,
        string directory,
        string expectedStatus,
        string? expectedReason,
        int expectedManifestCount)
    {
        // Arrange
        var logger = new TestLogger();
        var apiHandler = new TestApiHandler();
        var discoveryWorker = TestDiscoveryWorker.FromResults();
        var worker = new GraphWorker("test-job-id", apiHandler, discoveryWorker, logger);

        // Act
        var result = worker.BuildDependencySubmission(discoveryResult, job, baseCommitSha, repoRoot, directory);

        // Assert
        Assert.NotNull(result);
        Assert.Equal(1, result.Version);
        Assert.Equal(baseCommitSha, result.Sha);
        Assert.Equal(expectedStatus, result.Metadata.Status);
        Assert.Equal(expectedReason, result.Metadata.Reason);
        Assert.Equal(expectedManifestCount, result.Manifests.Count);
        Assert.Equal($"nuget::{directory}", result.Metadata.ScannedManifestPath);
    }

    public static IEnumerable<object?[]> BuildDependencySubmissionTestData()
    {
        var job = new Job
        {
            Source = new JobSource
            {
                Provider = "github",
                Repo = "test/repo",
                Directory = "/",
                Branch = "main"
            }
        };

        // Test case 1: No projects discovered
        yield return
        [
            // discoveryResult
            new WorkspaceDiscoveryResult
            {
                Path = "/src",
                Projects = ImmutableArray<ProjectDiscoveryResult>.Empty
            },
            // job
            job,
            // baseCommitSha
            "abc123",
            // repoRoot
            "/repo",
            // directory
            "/src",
            // expectedStatus
            "skipped",
            // expectedReason
            "missing manifest files",
            // expectedManifestCount
            0
        ];

        // Test case 2: Project with no dependencies
        yield return
        [
            // discoveryResult
            new WorkspaceDiscoveryResult
            {
                Path = "/src",
                Projects =
                [
                    new ProjectDiscoveryResult
                    {
                        FilePath = "project.csproj",
                        Dependencies = ImmutableArray<Dependency>.Empty,
                        ImportedFiles = ImmutableArray<string>.Empty,
                        AdditionalFiles = ImmutableArray<string>.Empty
                    }
                ]
            },
            // job
            job,
            // baseCommitSha
            "abc123",
            // repoRoot
            "/repo",
            // directory
            "/src",
            // expectedStatus
            "skipped",
            // expectedReason
            "missing manifest files",
            // expectedManifestCount
            0
        ];

        // Test case 3: Project with dependencies
        yield return
        [
            // discoveryResult
            new WorkspaceDiscoveryResult
            {
                Path = "/src",
                Projects =
                [
                    new ProjectDiscoveryResult
                    {
                        FilePath = "project.csproj",
                        Dependencies =
                        [
                            new Dependency("Newtonsoft.Json", "13.0.3", DependencyType.PackageReference, IsTopLevel: true),
                            new Dependency("System.Text.Json", "8.0.0", DependencyType.PackageReference, IsTopLevel: false)
                        ],
                        ImportedFiles = ImmutableArray<string>.Empty,
                        AdditionalFiles = ImmutableArray<string>.Empty
                    }
                ]
            },
            // job
            job,
            // baseCommitSha
            "def456",
            // repoRoot
            "/repo",
            // directory
            "/src",
            // expectedStatus
            "ok",
            // expectedReason
            null,
            // expectedManifestCount
            1
        ];

        // Test case 4: Multiple projects with dependencies
        yield return
        [
            // discoveryResult
            new WorkspaceDiscoveryResult
            {
                Path = "/src",
                Projects =
                [
                    new ProjectDiscoveryResult
                    {
                        FilePath = "project1.csproj",
                        Dependencies =
                        [
                            new Dependency("Newtonsoft.Json", "13.0.3", DependencyType.PackageReference, IsTopLevel: true)
                        ],
                        ImportedFiles = ImmutableArray<string>.Empty,
                        AdditionalFiles = ImmutableArray<string>.Empty
                    },
                    new ProjectDiscoveryResult
                    {
                        FilePath = "project2.csproj",
                        Dependencies =
                        [
                            new Dependency("System.Text.Json", "8.0.0", DependencyType.PackageReference, IsTopLevel: true)
                        ],
                        ImportedFiles = ImmutableArray<string>.Empty,
                        AdditionalFiles = ImmutableArray<string>.Empty
                    }
                ]
            },
            // job
            job,
            // baseCommitSha
            "ghi789",
            // repoRoot
            "/repo",
            // directory
            "/src",
            // expectedStatus
            "ok",
            // expectedReason
            null,
            // expectedManifestCount
            2
        ];

        // Test case 5: Dependencies without versions (should be skipped)
        yield return
        [
            // discoveryResult
            new WorkspaceDiscoveryResult
            {
                Path = "/src",
                Projects =
                [
                    new ProjectDiscoveryResult
                    {
                        FilePath = "project.csproj",
                        Dependencies =
                        [
                            new Dependency("SomePackage", null, DependencyType.PackageReference, IsTopLevel: true)
                        ],
                        ImportedFiles = ImmutableArray<string>.Empty,
                        AdditionalFiles = ImmutableArray<string>.Empty
                    }
                ]
            },
            // job
            job,
            // baseCommitSha
            "jkl012",
            // repoRoot
            "/repo",
            // directory
            "/src",
            // expectedStatus
            "skipped",
            // expectedReason
            "missing manifest files",
            // expectedManifestCount
            0
        ];
    }

    [Theory]
    [MemberData(nameof(DependencyConversionTestData))]
    public void BuildDependencySubmission_CorrectlyConvertsDependencies(
        Dependency dependency,
        string expectedPackageUrl,
        string expectedRelationship,
        string expectedScope)
    {
        // Arrange
        var logger = new TestLogger();
        var apiHandler = new TestApiHandler();
        var discoveryWorker = TestDiscoveryWorker.FromResults();
        var worker = new GraphWorker("test-job-id", apiHandler, discoveryWorker, logger);

        var discoveryResult = new WorkspaceDiscoveryResult
        {
            Path = "/src",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "project.csproj",
                    Dependencies = [dependency],
                    ImportedFiles = ImmutableArray<string>.Empty,
                    AdditionalFiles = ImmutableArray<string>.Empty
                }
            ]
        };

        var job = new Job
        {
            Source = new JobSource
            {
                Provider = "github",
                Repo = "test/repo",
                Directory = "/"
            }
        };

        // Act
        var result = worker.BuildDependencySubmission(discoveryResult, job, "abc123", "/repo", "/src");

        // Assert
        Assert.NotNull(result);
        Assert.Single(result.Manifests);

        var manifest = result.Manifests.Values.First();
        Assert.Contains(expectedPackageUrl, manifest.Resolved.Keys);

        var resolvedDep = manifest.Resolved[expectedPackageUrl];
        Assert.Equal(expectedPackageUrl, resolvedDep.PackageUrl);
        Assert.Equal(expectedRelationship, resolvedDep.Relationship);
        Assert.Equal(expectedScope, resolvedDep.Scope);
    }

    public static IEnumerable<object[]> DependencyConversionTestData()
    {
        // Direct runtime dependency
        yield return
        [
            // dependency
            new Dependency("Newtonsoft.Json", "13.0.3", DependencyType.PackageReference, IsTopLevel: true),
            // expectedPackageUrl
            "pkg:nuget/Newtonsoft.Json@13.0.3",
            // expectedRelationship
            "direct",
            // expectedScope
            "runtime"
        ];

        // Indirect runtime dependency
        yield return
        [
            // dependency
            new Dependency("System.Text.Json", "8.0.0", DependencyType.PackageReference, IsTopLevel: false),
            // expectedPackageUrl
            "pkg:nuget/System.Text.Json@8.0.0",
            // expectedRelationship
            "indirect",
            // expectedScope
            "runtime"
        ];

        // PackageVersion dependency
        yield return
        [
            // dependency
            new Dependency("Microsoft.Extensions.Logging", "7.0.0", DependencyType.PackageVersion, IsTopLevel: true),
            // expectedPackageUrl
            "pkg:nuget/Microsoft.Extensions.Logging@7.0.0",
            // expectedRelationship
            "direct",
            // expectedScope
            "runtime"
        ];
    }
}
