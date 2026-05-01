using System.Collections.Immutable;
using System.Text.Json;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Graph;
using NuGetUpdater.Core.Run;

using Xunit;

namespace NuGetUpdater.Core.Test.Graph;

public class DependencyGrapherTests
{
    [Fact]
    public void BuildPurl_ReturnsCorrectFormat()
    {
        var purl = DependencyGrapher.BuildPurl("Newtonsoft.Json", "13.0.1");
        Assert.Equal("pkg:nuget/Newtonsoft.Json@13.0.1", purl);
    }

    [Fact]
    public void BuildPurl_HandlesPreReleaseVersions()
    {
        var purl = DependencyGrapher.BuildPurl("Microsoft.Extensions.Hosting", "8.0.0-rc.2.23479.6");
        Assert.Equal("pkg:nuget/Microsoft.Extensions.Hosting@8.0.0-rc.2.23479.6", purl);
    }

    [Theory]
    [InlineData(DependencyType.PackageReference, "runtime")]
    [InlineData(DependencyType.PackagesConfig, "runtime")]
    [InlineData(DependencyType.PackageVersion, "runtime")]
    [InlineData(DependencyType.GlobalPackageReference, "runtime")]
    [InlineData(DependencyType.DotNetTool, "development")]
    [InlineData(DependencyType.MSBuildSdk, "development")]
    [InlineData(DependencyType.Unknown, "runtime")]
    public void GetScope_MapsCorrectly(DependencyType type, string expectedScope)
    {
        Assert.Equal(expectedScope, DependencyGrapher.GetScope(type));
    }

    [Theory]
    [InlineData("main", "refs/heads/main")]
    [InlineData("develop", "refs/heads/develop")]
    public void NormalizeRef_AddsPrefixForPlainBranch(string input, string expected)
    {
        Assert.Equal(expected, DependencyGrapher.NormalizeRef(input));
    }

    [Theory]
    [InlineData("refs/heads/main", "refs/heads/main")]
    [InlineData("/refs/heads/main", "refs/heads/main")]
    public void NormalizeRef_PreservesRefPrefix(string input, string expected)
    {
        Assert.Equal(expected, DependencyGrapher.NormalizeRef(input));
    }

    [Fact]
    public void BuildSubmission_WithSingleProject_ReturnsCorrectPayload()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "MyApp/MyApp.csproj",
                    Dependencies =
                    [
                        new Dependency("Newtonsoft.Json", "13.0.1", DependencyType.PackageReference, IsTopLevel: true),
                        new Dependency("System.Text.Json", "8.0.0", DependencyType.PackageReference, IsTopLevel: false),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        Assert.Equal(1, payload.Version);
        Assert.Equal("abc123", payload.Sha);
        Assert.Equal("refs/heads/main", payload.Ref);
        Assert.Equal("job-123", payload.Job.Id);
        Assert.Equal("ok", payload.Metadata.Status);
        Assert.Null(payload.Metadata.Reason);

        Assert.Single(payload.Manifests);
        var manifest = payload.Manifests.Values.First();
        Assert.Equal("nuget", manifest.Metadata.Ecosystem);
        Assert.Equal(2, manifest.Resolved.Count);

        var newtonsoft = manifest.Resolved["pkg:nuget/Newtonsoft.Json@13.0.1"];
        Assert.Equal("direct", newtonsoft.Relationship);
        Assert.Equal("runtime", newtonsoft.Scope);
        Assert.Empty(newtonsoft.Dependencies);

        var systemText = manifest.Resolved["pkg:nuget/System.Text.Json@8.0.0"];
        Assert.Equal("indirect", systemText.Relationship);
        Assert.Equal("runtime", systemText.Scope);
    }

    [Fact]
    public void BuildSubmission_WithMultipleProjects_ReturnsMultipleManifests()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "App/App.csproj",
                    Dependencies =
                    [
                        new Dependency("Newtonsoft.Json", "13.0.1", DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                new ProjectDiscoveryResult
                {
                    FilePath = "Lib/Lib.csproj",
                    Dependencies =
                    [
                        new Dependency("Serilog", "3.1.1", DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        Assert.Equal(2, payload.Manifests.Count);
        Assert.Equal("ok", payload.Metadata.Status);
    }

    [Fact]
    public void BuildSubmission_WithGlobalJson_IncludesAsManifest()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects = [],
            GlobalJson = new GlobalJsonDiscoveryResult
            {
                FilePath = "global.json",
                Dependencies =
                [
                    new Dependency("Microsoft.Build.Traversal", "4.1.0", DependencyType.MSBuildSdk, IsTopLevel: true),
                ],
            },
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        Assert.Single(payload.Manifests);
        var manifest = payload.Manifests.Values.First();
        var dep = manifest.Resolved.Values.First();
        Assert.Equal("development", dep.Scope);
    }

    [Fact]
    public void BuildSubmission_WithDotNetToolsJson_IncludesAsManifest()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects = [],
            DotNetToolsJson = new DotNetToolsJsonDiscoveryResult
            {
                FilePath = ".config/dotnet-tools.json",
                Dependencies =
                [
                    new Dependency("dotnet-ef", "8.0.0", DependencyType.DotNetTool, IsTopLevel: true),
                ],
            },
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        Assert.Single(payload.Manifests);
        var dep = payload.Manifests.Values.First().Resolved.Values.First();
        Assert.Equal("pkg:nuget/dotnet-ef@8.0.0", dep.PackageUrl);
        Assert.Equal("development", dep.Scope);
        Assert.Equal("direct", dep.Relationship);
    }

    [Fact]
    public void BuildSubmission_WithEmptyDiscovery_ReturnsSkippedStatus()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects = [],
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        Assert.Equal("skipped", payload.Metadata.Status);
        Assert.Equal("missing manifest files", payload.Metadata.Reason);
        Assert.Empty(payload.Manifests);
    }

    [Fact]
    public void BuildSubmission_SkipsDependenciesWithNullVersion()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "App.csproj",
                    Dependencies =
                    [
                        new Dependency("HasVersion", "1.0.0", DependencyType.PackageReference, IsTopLevel: true),
                        new Dependency("NoVersion", null, DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        var manifest = payload.Manifests.Values.First();
        Assert.Single(manifest.Resolved);
        Assert.Contains("pkg:nuget/HasVersion@1.0.0", manifest.Resolved.Keys);
    }

    [Fact]
    public void BuildSubmission_SkipsFailedProjects()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "Good.csproj",
                    IsSuccess = true,
                    Dependencies =
                    [
                        new Dependency("Pkg", "1.0.0", DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                },
                new ProjectDiscoveryResult
                {
                    FilePath = "Bad.csproj",
                    IsSuccess = false,
                    Dependencies =
                    [
                        new Dependency("Other", "2.0.0", DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        Assert.Single(payload.Manifests);
    }

    [Fact]
    public void BuildFailedSubmission_ReturnsFailedStatus()
    {
        var payload = DependencyGrapher.BuildFailedSubmission(
            "/", "job-123", "abc123", "main", "1.0.0", "some_error");

        Assert.Equal("failed", payload.Metadata.Status);
        Assert.Equal("some_error", payload.Metadata.Reason);
        Assert.Empty(payload.Manifests);
    }

    [Fact]
    public void BuildCorrelator_WithRootPath()
    {
        var correlator = DependencyGrapher.BuildCorrelator("/");
        Assert.Equal("dependabot-nuget", correlator);
    }

    [Fact]
    public void BuildCorrelator_WithSubdirectory()
    {
        var correlator = DependencyGrapher.BuildCorrelator("/src/app");
        Assert.Equal("dependabot-nuget-src-app", correlator);
    }

    [Fact]
    public void BuildSubmission_PayloadSerializesToCorrectJson()
    {
        var discovery = new WorkspaceDiscoveryResult
        {
            Path = "/",
            Projects =
            [
                new ProjectDiscoveryResult
                {
                    FilePath = "App.csproj",
                    Dependencies =
                    [
                        new Dependency("Newtonsoft.Json", "13.0.1", DependencyType.PackageReference, IsTopLevel: true),
                    ],
                    ImportedFiles = [],
                    AdditionalFiles = [],
                }
            ],
        };

        var payload = DependencyGrapher.BuildSubmission(discovery, "job-123", "abc123", "main", "1.0.0");

        // Serialize using the same options as HttpApiHandler to verify wire format
        var json = JsonSerializer.Serialize(payload, HttpApiHandler.SerializerOptions);

        Assert.Contains("\"package_url\"", json);
        Assert.Contains("\"pkg:nuget/Newtonsoft.Json@13.0.1\"", json);
        Assert.Contains("\"relationship\"", json);
        Assert.Contains("\"direct\"", json);
        Assert.Contains("\"scope\"", json);
        Assert.Contains("\"runtime\"", json);
        Assert.Contains("\"source_location\"", json);
        Assert.Contains("\"scanned_manifest_path\"", json);
    }
}
