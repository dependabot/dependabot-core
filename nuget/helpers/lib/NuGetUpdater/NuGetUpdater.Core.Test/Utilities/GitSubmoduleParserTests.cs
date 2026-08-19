using System.Collections.Immutable;

using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class GitSubmoduleParserTests
{
    [Theory]
    [MemberData(nameof(ParseSubmodulePathsData))]
    public void ParseSubmodulePaths(string gitmodulesContent, string[] expectedPaths)
    {
        var result = GitSubmoduleParser.ParseSubmodulePaths(gitmodulesContent);
        Assert.Equal(expectedPaths, result);
    }

    public static IEnumerable<object[]> ParseSubmodulePathsData()
    {
        // empty content returns no paths
        yield return
        [
            // gitmodulesContent
            "",
            // expectedPaths
            Array.Empty<string>(),
        ];

        // single submodule
        yield return
        [
            // gitmodulesContent
            """
            [submodule "external/lib"]
                path = external/lib
                url = https://github.com/example/lib.git
            """,
            // expectedPaths
            new[] { "external/lib" },
        ];

        // multiple submodules
        yield return
        [
            // gitmodulesContent
            """
            [submodule "vendor/lib1"]
                path = vendor/lib1
                url = https://github.com/example/lib1.git
            [submodule "vendor/lib2"]
                path = vendor/lib2
                url = https://github.com/example/lib2.git
            [submodule "third_party/tools"]
                path = third_party/tools
                url = https://github.com/example/tools.git
            """,
            // expectedPaths
            new[] { "vendor/lib1", "vendor/lib2", "third_party/tools" },
        ];

        // Windows path separators are normalized to forward slashes
        yield return
        [
            // gitmodulesContent
            """
            [submodule "vendor\lib"]
                path = vendor\lib
                url = https://github.com/example/lib.git
            """,
            // expectedPaths
            new[] { "vendor/lib" },
        ];

        // no spaces around equals sign
        yield return
        [
            // gitmodulesContent
            """
            [submodule "external/lib"]
                path=external/lib
                url=https://github.com/example/lib.git
            """,
            // expectedPaths
            new[] { "external/lib" },
        ];

        // non-path keys are ignored
        yield return
        [
            // gitmodulesContent
            """
            [submodule "external/lib"]
                url = https://github.com/example/lib.git
                branch = main
                path = external/lib
                update = rebase
            """,
            // expectedPaths
            new[] { "external/lib" },
        ];
    }

    [Theory]
    [InlineData("vendor/lib/project.csproj", true)]
    [InlineData("vendor/lib", true)]
    [InlineData("vendor/lib/sub/deep/file.cs", true)]
    [InlineData("vendor/other/project.csproj", false)]
    [InlineData("src/project.csproj", false)]
    [InlineData("vendorlib/project.csproj", false)]
    [InlineData("src/../vendor/lib/project.csproj", true)]
    [InlineData("vendor/lib/../lib/project.csproj", true)]
    [InlineData("vendor/lib/../other/project.csproj", false)]
    public void IsPathInSubmodule_CorrectlyIdentifiesSubmodulePaths(string path, bool expected)
    {
        var submodulePaths = ImmutableArray.Create("vendor/lib", "third_party/tools");
        var result = GitSubmoduleParser.IsPathInSubmodule(path, submodulePaths);
        Assert.Equal(expected, result);
    }

    [Fact]
    public void IsPathInSubmodule_ReturnsFalse_WhenNoSubmodules()
    {
        var result = GitSubmoduleParser.IsPathInSubmodule("src/project.csproj", []);
        Assert.False(result);
    }

    [Fact]
    public void IsPathInSubmodule_IsCaseInsensitive()
    {
        var submodulePaths = ImmutableArray.Create("Vendor/Lib");
        var result = GitSubmoduleParser.IsPathInSubmodule("vendor/lib/project.csproj", submodulePaths);
        Assert.True(result);
    }
}
