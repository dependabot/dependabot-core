using NuGetUpdater.Core.Utilities;

using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class GitIgnoreParserTests
{
    [Theory]
    [MemberData(nameof(BasicPatternMatchingData))]
    public void BasicPatternMatching(string gitignoreContent, string testPath, bool expectedIgnored)
    {
        var parser = CreateParserFromContent(gitignoreContent, pathPrefix: "");
        Assert.Equal(expectedIgnored, parser.IsIgnored(testPath));
    }

    public static IEnumerable<object[]> BasicPatternMatchingData()
    {
        // exact file name match
        yield return ["file.txt", "file.txt", true];
        yield return ["file.txt", "other.txt", false];

        // unrooted pattern matches at any depth
        yield return ["*.log", "debug.log", true];
        yield return ["*.log", "src/debug.log", true];
        yield return ["*.log", "src/deep/nested/debug.log", true];
        yield return ["*.log", "debug.txt", false];

        // pattern containing a slash is anchored relative to .gitignore location (per git spec)
        yield return ["src/file.txt", "src/file.txt", true];
        yield return ["src/file.txt", "other/src/file.txt", false];

        // wildcard in middle of pattern
        yield return ["doc/*.txt", "doc/readme.txt", true];
        yield return ["doc/*.txt", "doc/sub/readme.txt", false];

        // double star matches across directories
        yield return ["**/logs", "logs", true];
        yield return ["**/logs", "src/logs", true];
        yield return ["**/logs", "src/deep/logs", true];

        // double star in middle
        yield return ["src/**/file.txt", "src/file.txt", true];
        yield return ["src/**/file.txt", "src/a/file.txt", true];
        yield return ["src/**/file.txt", "src/a/b/file.txt", true];

        // question mark matches single char
        yield return ["file?.txt", "file1.txt", true];
        yield return ["file?.txt", "fileAB.txt", false];

        // directory-only pattern (trailing slash)
        yield return ["build/", "build/output.dll", true];
        yield return ["build/", "src/build/output.dll", true];

        // comment lines are ignored
        yield return ["# this is a comment\n*.log", "debug.log", true];
        yield return ["# this is a comment\n*.log", "# this is a comment", false];

        // blank lines are ignored
        yield return ["\n\n*.log\n\n", "debug.log", true];
    }

    [Theory]
    [MemberData(nameof(NegationPatternData))]
    public void NegationPatterns(string gitignoreContent, string testPath, bool expectedIgnored)
    {
        var parser = CreateParserFromContent(gitignoreContent, pathPrefix: "");
        Assert.Equal(expectedIgnored, parser.IsIgnored(testPath));
    }

    public static IEnumerable<object[]> NegationPatternData()
    {
        // negation re-includes a previously excluded file
        yield return ["*.log\n!important.log", "debug.log", true];
        yield return ["*.log\n!important.log", "important.log", false];

        // negation only applies if previously matched
        yield return ["!random.txt", "random.txt", false];

        // order matters: last matching rule wins
        yield return ["*.log\n!important.log\n*.log", "important.log", true];
    }

    [Fact]
    public void GitIgnoreInSubdirectory_OnlyAffectsFilesUnderThatDirectory()
    {
        using var tempDir = new TempGitIgnoreDirectory();
        tempDir.WriteFile(".gitignore", "root-ignored.txt");
        tempDir.WriteFile("src/.gitignore", "sub-ignored.txt");
        // create the actual files so directory enumeration works
        tempDir.WriteFile("root-ignored.txt", "");
        tempDir.WriteFile("other.txt", "");
        tempDir.WriteFile("src/sub-ignored.txt", "");
        tempDir.WriteFile("src/kept.txt", "");
        tempDir.WriteFile("lib/sub-ignored.txt", "");

        var parser = GitIgnoreParser.FromRepoRoot(tempDir.RootPath);

        // root .gitignore applies everywhere (unrooted pattern)
        Assert.True(parser.IsIgnored("root-ignored.txt"));
        Assert.True(parser.IsIgnored("src/root-ignored.txt"));

        // src/.gitignore applies under src/
        Assert.True(parser.IsIgnored("src/sub-ignored.txt"));

        // src/.gitignore should NOT affect lib/ (pattern is prefixed with src/)
        Assert.False(parser.IsIgnored("lib/sub-ignored.txt"));

        // non-ignored files remain accessible
        Assert.False(parser.IsIgnored("other.txt"));
        Assert.False(parser.IsIgnored("src/kept.txt"));
    }

    [Fact]
    public void MultipleGitIgnoreFilesAtDifferentLevels()
    {
        using var tempDir = new TempGitIgnoreDirectory();
        tempDir.WriteFile(".gitignore", "*.tmp");
        tempDir.WriteFile("src/.gitignore", "generated/");
        tempDir.WriteFile("src/app/.gitignore", "local.config");
        // create dirs so enumeration works
        tempDir.WriteFile("src/app/local.config", "");
        tempDir.WriteFile("src/generated/output.cs", "");
        tempDir.WriteFile("docs/notes.tmp", "");

        var parser = GitIgnoreParser.FromRepoRoot(tempDir.RootPath);

        // root pattern *.tmp applies at any depth
        Assert.True(parser.IsIgnored("docs/notes.tmp"));
        Assert.True(parser.IsIgnored("src/app/cache.tmp"));

        // src/.gitignore: "generated/" directory pattern
        Assert.True(parser.IsIgnored("src/generated/output.cs"));
        Assert.False(parser.IsIgnored("docs/generated/output.cs"));

        // src/app/.gitignore: "local.config" unrooted
        Assert.True(parser.IsIgnored("src/app/local.config"));
        Assert.False(parser.IsIgnored("src/local.config"));
    }

    [Fact]
    public void RootedPatternInSubdirectoryGitIgnore()
    {
        using var tempDir = new TempGitIgnoreDirectory();
        // A rooted pattern (contains /) in a subdirectory .gitignore
        tempDir.WriteFile("lib/.gitignore", "obj/debug.dll");
        tempDir.WriteFile("lib/obj/debug.dll", "");
        tempDir.WriteFile("lib/obj/release.dll", "");

        var parser = GitIgnoreParser.FromRepoRoot(tempDir.RootPath);

        Assert.True(parser.IsIgnored("lib/obj/debug.dll"));
        Assert.False(parser.IsIgnored("lib/obj/release.dll"));
        // should not match in other directories
        Assert.False(parser.IsIgnored("src/obj/debug.dll"));
    }

    [Fact]
    public void CharacterClassPatterns()
    {
        var parser = CreateParserFromContent("[Bb]uild/", pathPrefix: "");
        Assert.True(parser.IsIgnored("Build/output.dll"));
        Assert.True(parser.IsIgnored("build/output.dll"));
        Assert.False(parser.IsIgnored("rebuild/output.dll"));
    }

    [Fact]
    public void PatternWithLeadingSlashIsRooted()
    {
        // leading slash means pattern is rooted relative to gitignore location
        var parser = CreateParserFromContent("/build\n/dist", pathPrefix: "");
        Assert.True(parser.IsIgnored("build"));
        Assert.True(parser.IsIgnored("build/output.dll"));
        Assert.True(parser.IsIgnored("dist"));
        Assert.False(parser.IsIgnored("src/build"));
        Assert.False(parser.IsIgnored("src/dist"));
    }

    private static GitIgnoreParser CreateParserFromContent(string content, string pathPrefix)
    {
        // Use a temp directory with just the gitignore content at the root
        using var tempDir = new TempGitIgnoreDirectory();
        tempDir.WriteFile(".gitignore", content);
        return GitIgnoreParser.FromRepoRoot(tempDir.RootPath);
    }

    /// <summary>
    /// Helper to create a temporary directory structure for testing GitIgnoreParser.
    /// </summary>
    private sealed class TempGitIgnoreDirectory : IDisposable
    {
        public string RootPath { get; }

        public TempGitIgnoreDirectory()
        {
            RootPath = Path.Combine(Path.GetTempPath(), $"gitignore-test-{Guid.NewGuid():N}");
            Directory.CreateDirectory(RootPath);
        }

        public void WriteFile(string relativePath, string content)
        {
            var fullPath = Path.Combine(RootPath, relativePath.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            File.WriteAllText(fullPath, content);
        }

        public void Dispose()
        {
            try { Directory.Delete(RootPath, true); } catch { }
        }
    }
}
