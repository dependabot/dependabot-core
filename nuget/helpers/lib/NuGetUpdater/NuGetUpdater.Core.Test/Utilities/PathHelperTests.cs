using Xunit;

namespace NuGetUpdater.Core.Test.Utilities;

public class PathHelperTests
{
    [Theory]
    [InlineData("a/b/c", "a/b/c")]
    [InlineData("a/b/../c", "a/c")]
    [InlineData("a/..//c", "c")]
    [InlineData("/a/b/c", "/a/b/c")]
    [InlineData("/a/b/../c", "/a/c")]
    [InlineData("/a/..//c", "/c")]
    [InlineData("a/b/./c", "a/b/c")]
    [InlineData("a/../../b", "b")]
    [InlineData("../../../a/b", "a/b")]
    public void VerifyNormalizeUnixPathParts(string input, string expected)
    {
        var actual = input.NormalizeUnixPathParts();
        Assert.Equal(expected, actual);
    }

    [Fact]
    public void VerifyResolveCaseInsensitivePath()
    {
        using var temp = new TemporaryDirectory();
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "a"));
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "a", "packages.config"), "");

        var repoRootPath = Path.Combine(temp.DirectoryPath, "src");

        var resolvedPath = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Combine(repoRootPath, "A", "PACKAGES.CONFIG"), repoRootPath);

        var expected = Path.Combine(temp.DirectoryPath, "src", "a", "packages.config").NormalizePathToUnix();
        Assert.Equal(expected, resolvedPath!.First());
    }

    [Theory]
    [MemberData(nameof(DirectoryPatternMatchTestData))]
    public async Task DirectoryPatternMatch(string rawSearchPattern, string[] directoriesOnDisk, string[] expectedDirectories)
    {
        // arrange
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync([.. directoriesOnDisk.Select(d => (Path.Combine(d, "file.txt"), "contents irrelevant"))]);

        // test both rooted and unrooted patterns
        var unrootedSearchPattern = rawSearchPattern.TrimStart('/');
        var rootedSearchPattern = rawSearchPattern.EnsurePrefix("/");
        foreach (var searchPattern in new[] { unrootedSearchPattern, rootedSearchPattern })
        {
            // act
            var actualDirectories = PathHelper.GetMatchingDirectoriesUnder(tempDir.DirectoryPath, searchPattern, caseSensitive: true).ToArray();

            // assert
            AssertEx.Equal(expectedDirectories, actualDirectories);
        }
    }

    public static IEnumerable<object[]> DirectoryPatternMatchTestData()
    {
        // root syntax 1
        yield return
        [
            // searchPattern
            "/",
            // directoriesOnDisk
            new[]
            {
                "src/client/android"
            },
            // expectedDirectories
            new[]
            {
                "/"
            }
        ];

        // root syntax 2
        yield return
        [
            // searchPattern
            ".",
            // directoriesOnDisk
            new[]
            {
                "src/client/android"
            },
            // expectedDirectories
            new[]
            {
                "/"
            }
        ];

        // no pattern, no match
        yield return
        [
            // searchPattern
            "src/client/winphone",
            // directoriesOnDisk
            new[]
            {
                "src/client/android",
                "src/client/android/ui",
                "src/client/ios",
                "src/client/ios/ui"
            },
            // expectedDirectories
            Array.Empty<string>()
        ];

        // no pattern, single match
        yield return
        [
            // searchPattern
            "src/client/android",
            // directoriesOnDisk
            new[]
            {
                "src/client/android",
                "src/client/android/ui",
                "src/client/android-old",
                "src/client/ios",
                "src/client/ios/ui"
            },
            // expectedDirectories
            new[]
            {
                "/src/client/android"
            }
        ];

        // no pattern, windows directory separator, single match
        yield return
        [
            // searchPattern
            @"src\client\android",
            // directoriesOnDisk
            new[]
            {
                "src/client/android",
                "src/client/android/ui",
                "src/client/ios",
                "src/client/ios/ui"
            },
            // expectedDirectories
            new[]
            {
                "/src/client/android"
            }
        ];

        // single level wildcard
        yield return
        [
            // searchPattern
            "src/client/*/ui",
            // directoriesOnDisk
            new[]
            {
                "src/client/android/ui",
                "src/client/ios/ui",
                "src/client/winphone/deprecated/ui",
                "src/internal/android/ui",
                "src/legacy/ui"
            },
            // expectedDirectories
            new[]
            {
                "/src/client/android/ui",
                "/src/client/ios/ui",
            }
        ];

        // single level partial wildcard
        yield return
        [
            // searchPattern
            "src/client/a*/ui",
            // directoriesOnDisk
            new[]
            {
                "src/client/android/ui",
                "src/client/ios/ui",
                "src/internal/android/ui",
                "src/legacy/ui"
            },
            // expectedDirectories
            new[]
            {
                "/src/client/android/ui",
            }
        ];

        // multi level wildcard
        yield return
        [
            // searchPattern
            "src/*/*/ui",
            // directoriesOnDisk
            new[]
            {
                "src/client/android/ui",
                "src/client/ios/ui",
                "src/client/winphone/deprecated/ui",
                "src/internal/android/ui",
                "src/legacy/ui"
            },
            // expectedDirectories
            new[]
            {
                "/src/client/android/ui",
                "/src/client/ios/ui",
                "/src/internal/android/ui",
            }
        ];

        // recursive wildcard with suffix
        yield return
        [
            // searchPattern
            "src/**/ui",
            // directoriesOnDisk
            new[]
            {
                "src/client/android/ui",
                "src/client/ios/ui",
                "src/internal/ui",
                "src/server/windows/container"
            },
            // expectedDirectories
            new[]
            {
                "/src/client/android/ui",
                "/src/client/ios/ui",
                "/src/internal/ui"
            }
        ];

        // recursive wildcard from beginning to end
        yield return
        [
            // searchPattern
            "**/*",
            // directoriesOnDisk
            new[]
            {
                "src/client/android/ui",
                "src/client/ios/ui"
            },
            // expectedDirectories
            new[]
            {
                "/",
                "/src",
                "/src/client",
                "/src/client/android",
                "/src/client/android/ui",
                "/src/client/ios",
                "/src/client/ios/ui"
            }
        ];

        // recursive wildcard with prefix to end
        yield return
        [
            // searchPattern
            "src/**/*",
            // directoriesOnDisk
            new[]
            {
                "src/client/android/ui",
                "src/client/ios/ui",
                "src-dont-include-this/ui"
            },
            // expectedDirectories
            new[]
            {
                "/src",
                "/src/client",
                "/src/client/android",
                "/src/client/android/ui",
                "/src/client/ios",
                "/src/client/ios/ui"
            }
        ];

        // leading and trailing slashes
        yield return
        [
            // searchPattern
            "/src/",
            // directoriesOnDisk
            new[]
            {
                "src",
                "tests"
            },
            // expectedDirectories
            new[]
            {
                "/src"
            }
        ];
    }

    [LinuxOnlyFact]
    public void VerifyMultipleMatchingPathsReturnsAllPaths()
    {
        using var temp = new TemporaryDirectory();
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "a"));
        Directory.CreateDirectory(Path.Combine(temp.DirectoryPath, "src", "A"));

        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "a", "packages.config"), "");
        File.WriteAllText(Path.Combine(temp.DirectoryPath, "src", "A", "packages.config"), "");

        var repoRootPath = Path.Combine(temp.DirectoryPath, "src");

        var resolvedPaths = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Combine(repoRootPath, "A", "PACKAGES.CONFIG"), repoRootPath);

        var expected = new[]
        {
            Path.Combine(temp.DirectoryPath, "src", "A", "packages.config").NormalizePathToUnix(),
            Path.Combine(temp.DirectoryPath, "src", "a", "packages.config").NormalizePathToUnix(),
        };

        AssertEx.Equal(expected, resolvedPaths!);
    }

    [LinuxOnlyFact]
    public async Task FilesWithDifferentlyCasedDirectoriesCanBeResolved()
    {
        // arrange
        using var temp = new TemporaryDirectory();
        var testFile1 = "src/project1/project1.csproj";
        var testFile2 = "SRC/project2/project2.csproj";
        var testFiles = new[] { testFile1, testFile2 };
        foreach (var testFile in testFiles)
        {
            var fullPath = Path.Join(temp.DirectoryPath, testFile); Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            await File.WriteAllTextAsync(fullPath, "");
        }

        // act        
        var actualFile1 = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Join(temp.DirectoryPath, testFile1), temp.DirectoryPath);
        var actualFile2 = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(Path.Join(temp.DirectoryPath, testFile2), temp.DirectoryPath);

        // assert        
        Assert.EndsWith(testFile1, actualFile1![0]); Assert.EndsWith(testFile2, actualFile2![0]);
    }
}
