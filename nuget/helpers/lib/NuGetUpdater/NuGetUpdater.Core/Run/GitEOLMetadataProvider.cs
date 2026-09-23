using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Run;

internal sealed class GitEOLMetadataProvider : IEOLMetadataProvider
{
    public async Task<Dictionary<string, EOLType>> GetIndexEOLsAsync(
        DirectoryInfo repoContentsPath,
        IReadOnlyCollection<string> repoRelativePaths)
    {
        if (repoRelativePaths.Count == 0)
        {
            return new Dictionary<string, EOLType>(StringComparer.Ordinal);
        }

        var arguments = new List<string>
        {
            "--literal-pathspecs",
            "ls-files",
            "--eol",
            "-z",
            "--",
        };
        arguments.AddRange(repoRelativePaths);

        var (exitCode, stdout, stderr) = await ProcessEx.RunAsync("git", arguments, repoContentsPath.FullName);
        if (exitCode != 0)
        {
            throw new InvalidOperationException($"Unable to determine Git index line endings:\n{stderr}");
        }

        return ParseOutput(stdout);
    }

    internal static Dictionary<string, EOLType> ParseOutput(string output)
    {
        var result = new Dictionary<string, EOLType>(StringComparer.Ordinal);
        foreach (var record in output.Split('\0', StringSplitOptions.RemoveEmptyEntries))
        {
            var separatorIndex = record.IndexOf('\t');
            if (separatorIndex < 0)
            {
                continue;
            }

            var metadata = record[..separatorIndex];
            var path = record[(separatorIndex + 1)..].NormalizePathToUnix();
            var indexMetadata = metadata.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
            var eol = indexMetadata switch
            {
                "i/lf" => EOLType.LF,
                "i/crlf" => EOLType.CRLF,
                _ => (EOLType?)null,
            };

            if (eol is not null)
            {
                result[path] = eol.Value;
            }
        }

        return result;
    }
}
