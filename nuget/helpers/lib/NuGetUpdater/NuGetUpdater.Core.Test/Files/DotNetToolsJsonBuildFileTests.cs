using System.Diagnostics.CodeAnalysis;

using Xunit;

namespace NuGetUpdater.Core.Test.Files;

public class DotnetToolsJsonBuildFileTests
{
    [StringSyntax(StringSyntaxAttribute.Json)]
    const string DotnetToolsJson = """
        {
          "version": 1,
          "isRoot": true,
          "tools": {
            "microsoft.botsay": {
              "version": "1.0.0",
              "commands": [
                "botsay"
              ]
            },
            "dotnetsay": {
              "version": "2.1.3",
              "commands": [
                "dotnetsay"
              ]
            }
          }
        }
        """;

    private static DotNetToolsJsonBuildFile GetBuildFile() => new(
        basePath: "/",
        path: "/.config/dotnet-tools.json",
        contents: DotnetToolsJson,
        logger: new Logger(verbose: true));

    [Fact]
    public void GetDependencies_ReturnsDependencies()
    {
        var expectedDependencies = new List<Dependency>
        {
            new("microsoft.botsay", "1.0.0", DependencyType.DotNetTool),
            new("dotnetsay", "2.1.3", DependencyType.DotNetTool)
        };

        var buildFile = GetBuildFile();

        var dependencies = buildFile.GetDependencies();

        Assert.Equal(expectedDependencies, dependencies);
    }
}
