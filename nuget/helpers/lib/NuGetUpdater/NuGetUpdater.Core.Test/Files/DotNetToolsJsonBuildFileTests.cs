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
        logger: new TestLogger());

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

    [Theory]
    [InlineData(".config/dotnet-tools.json",
        "{\n  \"version\": 1,\n  \"tools\": {\n    \"dotnet-ef\": {\n      \"version\": \"10.0.11\"\n    }\n  }\n}",
        new[] { "tools", "dotnet-ef", "version" },
        "10.0.12",
        "{\n  \"version\": 1,\n  \"tools\": {\n    \"dotnet-ef\": {\n      \"version\": \"10.0.12\"\n    }\n  }\n}")]
    [InlineData(".config/dotnet-tools.json",
        "{\n  \"version\": 1,\n  \"tools\": {\n    \"dotnet-ef\": {\n      \"version\": \"10.0.11\"\n    }\n  }\n}\n",
        new[] { "tools", "dotnet-ef", "version" },
        "10.0.12",
        "{\n  \"version\": 1,\n  \"tools\": {\n    \"dotnet-ef\": {\n      \"version\": \"10.0.12\"\n    }\n  }\n}\n")]
    public async Task SaveAsync_PreservesFinalNewlineStateWhenSavingRealChanges(string relativePath,
        string originalContent,
        string[] propertyPathToModify,
        string newValue,
        string expectedReportedContent)
    {
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            (relativePath, originalContent));

        var filePath = Path.Combine(tempDirectory.DirectoryPath, relativePath);
        var buildFile = new GlobalJsonBuildFile(
            tempDirectory.DirectoryPath,
            filePath,
            originalContent,
            new TestLogger());

        buildFile.UpdateProperty(propertyPathToModify, newValue);

        var changed = await buildFile.SaveAsync();

        Assert.True(changed);
        Assert.Equal(expectedReportedContent, await File.ReadAllTextAsync(filePath, TestContext.Current.CancellationToken));
    }
}
