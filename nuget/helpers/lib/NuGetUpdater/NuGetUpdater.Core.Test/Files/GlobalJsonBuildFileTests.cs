using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Linq;

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
        repoRootPath: "/",
        path: "/global.json",
        contents: contents);

    [Fact]
    public void GlobalJson_GetDependencies_ReturnsDependencies()
    {
        var expectedDependencies = new List<Dependency>
        {
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
