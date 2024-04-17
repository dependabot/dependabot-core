using System.Diagnostics.CodeAnalysis;

using Xunit;

namespace NuGetUpdater.Core.Test.Files;

public class GlobalJsonBuildFileTests
{
    [StringSyntax(StringSyntaxAttribute.Json)]
    const string GlobalJson = """
        {
          "sdk": {
            "version": "6.0.405",
            "rollForward": "latestPatch"
          },
          "msbuild-sdks": {
            "My.Custom.Sdk": "5.0.0",
            "My.Other.Sdk": "1.0.0-beta"
          }
        }
        """;

    [StringSyntax(StringSyntaxAttribute.Json)]
    const string EmptyGlobalJson = """
        {
        }
        """;

    private static GlobalJsonBuildFile GetBuildFile(string contents) => new(
        basePath: "/",
        path: "/global.json",
        contents: contents,
        logger: new Logger(verbose: true));

    [Fact]
    public void GlobalJson_Malformed_DoesNotThrow()
    {
        var buildFile = GetBuildFile("""[{ "Random": "stuff"}]""");

        Assert.Null(buildFile.MSBuildSdks);
    }

    [Fact]
    public void GlobalJson_NotJson_DoesNotThrow()
    {
        var buildFile = GetBuildFile("not json");

        Assert.Null(buildFile.MSBuildSdks);
    }

    [Fact]
    public void GlobalJson_GetDependencies_ReturnsDependencies()
    {
        var expectedDependencies = new List<Dependency>
        {
            new("Microsoft.NET.Sdk", "6.0.405", DependencyType.MSBuildSdk),
            new("My.Custom.Sdk", "5.0.0", DependencyType.MSBuildSdk),
            new("My.Other.Sdk", "1.0.0-beta", DependencyType.MSBuildSdk)
        };

        var buildFile = GetBuildFile(GlobalJson);

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }

    [Fact]
    public void EmptyGlobalJson_GetDependencies_ReturnsNoDependencies()
    {
        var expectedDependencies = Enumerable.Empty<Dependency>();

        var buildFile = GetBuildFile(EmptyGlobalJson);

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }
}
