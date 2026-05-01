using System.Text.Json;

using NuGetUpdater.Core.Graph;

using Xunit;

namespace NuGetUpdater.Core.Test.Graph;

public class AssetsFileParserTests
{
    [Fact]
    public void ParseDependencyRelationships_ReturnsCorrectRelationships()
    {
        var assetsJson = new
        {
            targets = new Dictionary<string, object>
            {
                ["net8.0"] = new Dictionary<string, object>
                {
                    ["Microsoft.Extensions.DependencyInjection/8.0.0"] = new
                    {
                        type = "package",
                        dependencies = new Dictionary<string, string>
                        {
                            ["Microsoft.Extensions.DependencyInjection.Abstractions"] = "8.0.0"
                        }
                    },
                    ["Microsoft.Extensions.DependencyInjection.Abstractions/8.0.0"] = new
                    {
                        type = "package",
                        dependencies = new Dictionary<string, string>()
                    },
                    ["Newtonsoft.Json/13.0.1"] = new
                    {
                        type = "package",
                        dependencies = new Dictionary<string, string>()
                    }
                }
            }
        };

        var assetsPath = WriteTempAssetsFile(assetsJson);
        var knownPackages = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Microsoft.Extensions.DependencyInjection",
            "Microsoft.Extensions.DependencyInjection.Abstractions",
            "Newtonsoft.Json"
        };

        var relationships = AssetsFileParser.ParseDependencyRelationships(assetsPath, knownPackages, new TestLogger());

        Assert.Single(relationships);
        Assert.True(relationships.ContainsKey("Microsoft.Extensions.DependencyInjection"));
        Assert.Contains("Microsoft.Extensions.DependencyInjection.Abstractions",
            relationships["Microsoft.Extensions.DependencyInjection"]);
    }

    [Fact]
    public void ParseDependencyRelationships_FiltersByKnownPackages()
    {
        var assetsJson = new
        {
            targets = new Dictionary<string, object>
            {
                ["net8.0"] = new Dictionary<string, object>
                {
                    ["Serilog/3.1.1"] = new
                    {
                        type = "package",
                        dependencies = new Dictionary<string, string>
                        {
                            ["Serilog.Sinks.Console"] = "5.0.0",
                            ["UnknownPackage"] = "1.0.0"
                        }
                    },
                    ["Serilog.Sinks.Console/5.0.0"] = new
                    {
                        type = "package",
                        dependencies = new Dictionary<string, string>()
                    }
                }
            }
        };

        var assetsPath = WriteTempAssetsFile(assetsJson);
        var knownPackages = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "Serilog",
            "Serilog.Sinks.Console"
            // "UnknownPackage" is NOT in the known set
        };

        var relationships = AssetsFileParser.ParseDependencyRelationships(assetsPath, knownPackages, new TestLogger());

        Assert.Single(relationships);
        Assert.Single(relationships["Serilog"]);
        Assert.Contains("Serilog.Sinks.Console", relationships["Serilog"]);
    }

    [Fact]
    public void ParseDependencyRelationships_ReturnsEmptyForMissingFile()
    {
        var relationships = AssetsFileParser.ParseDependencyRelationships(
            "/nonexistent/path/project.assets.json",
            new HashSet<string>(),
            new TestLogger());

        Assert.Empty(relationships);
    }

    [Fact]
    public void ParseDependencyRelationships_ReturnsEmptyForMalformedJson()
    {
        var tempFile = Path.GetTempFileName();
        try
        {
            File.WriteAllText(tempFile, "not valid json");
            var relationships = AssetsFileParser.ParseDependencyRelationships(
                tempFile,
                new HashSet<string> { "SomePackage" },
                new TestLogger());

            Assert.Empty(relationships);
        }
        finally
        {
            File.Delete(tempFile);
        }
    }

    [Fact]
    public void BuildResolvedDependencies_WithRelationships_IncludesSubdependencyPurls()
    {
        var dependencies = new[]
        {
            new Dependency("ParentPkg", "1.0.0", DependencyType.PackageReference, IsTopLevel: true),
            new Dependency("ChildPkg", "2.0.0", DependencyType.PackageReference, IsTopLevel: false),
        };

        var relationships = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase)
        {
            ["ParentPkg"] = new(StringComparer.OrdinalIgnoreCase) { "ChildPkg" }
        };

        var resolved = DependencyGrapher.BuildResolvedDependencies(dependencies, relationships);

        var parent = resolved["pkg:nuget/ParentPkg@1.0.0"];
        Assert.Single(parent.Dependencies);
        Assert.Equal("pkg:nuget/ChildPkg@2.0.0", parent.Dependencies[0]);

        var child = resolved["pkg:nuget/ChildPkg@2.0.0"];
        Assert.Empty(child.Dependencies);
    }

    [Fact]
    public void BuildResolvedDependencies_WithoutRelationships_ReturnsEmptyDependencies()
    {
        var dependencies = new[]
        {
            new Dependency("SomePkg", "1.0.0", DependencyType.PackageReference, IsTopLevel: true),
        };

        var resolved = DependencyGrapher.BuildResolvedDependencies(dependencies, relationships: null);

        Assert.Empty(resolved["pkg:nuget/SomePkg@1.0.0"].Dependencies);
    }

    private static string WriteTempAssetsFile(object content)
    {
        var tempFile = Path.GetTempFileName();
        File.WriteAllText(tempFile, JsonSerializer.Serialize(content));
        return tempFile;
    }
}
