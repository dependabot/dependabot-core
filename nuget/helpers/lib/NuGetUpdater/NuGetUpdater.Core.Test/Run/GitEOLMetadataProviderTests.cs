using NuGetUpdater.Core.Run;

using Xunit;

using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Test.Run;

public class GitEOLMetadataProviderTests
{
    [Fact]
    public async Task ReadsNullDelimitedOutputFromGit()
    {
        using var tempDirectory = await TemporaryDirectory.CreateWithContentsAsync(
            (".gitattributes", "*.csproj text eol=crlf\n"),
            ("project.csproj", "<Project>\r\n  <PropertyGroup />\r\n</Project>\r\n"),
            ("src/other.csproj", "<Project>\r\n  <ItemGroup />\r\n</Project>\r\n"));
        var repoContentsPath = new DirectoryInfo(tempDirectory.DirectoryPath);

        await GitTestHelper.InitializeRepositoryAsync(
            repoContentsPath.FullName,
            [".gitattributes", "project.csproj", "src/other.csproj"]);

        var provider = new GitEOLMetadataProvider();
        var result = await provider.GetIndexEOLsAsync(repoContentsPath, ["project.csproj", "src/other.csproj"]);

        Assert.Equal(
            new Dictionary<string, EOLType>(StringComparer.OrdinalIgnoreCase)
            {
                ["project.csproj"] = EOLType.LF,
                ["src/other.csproj"] = EOLType.LF,
            },
            result);
    }

    [Fact]
    public void ParseOutputReturnsSupportedIndexLineEndings()
    {
        var output = string.Join('\0',
            "i/lf    w/crlf attr/text eol=crlf\tproject.csproj",
            "i/crlf  w/crlf attr/\tsrc/project with spaces.csproj",
            "i/lf    w/lf attr/\tsrc/Project with spaces.csproj",
            "i/mixed w/mixed attr/\tmixed.props",
            "i/-text w/-text attr/-text\tbinary.props",
            "");

        var result = GitEOLMetadataProvider.ParseOutput(output);

        Assert.Equal(
            new Dictionary<string, EOLType>(StringComparer.Ordinal)
            {
                ["project.csproj"] = EOLType.LF,
                ["src/project with spaces.csproj"] = EOLType.CRLF,
                ["src/Project with spaces.csproj"] = EOLType.LF,
            },
            result);
    }
}
