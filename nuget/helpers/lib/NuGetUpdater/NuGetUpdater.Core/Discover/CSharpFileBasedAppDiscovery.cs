using System.Collections.Immutable;
using System.Text.RegularExpressions;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

internal static partial class CSharpFileBasedAppDiscovery
{
    internal const string FileExtension = ".cs";
    internal const string DefaultTargetFramework = "net10.0";

    public static ImmutableArray<ProjectDiscoveryResult> Discover(string repoRootPath, string workspacePath, ILogger logger)
    {
        if (!Directory.Exists(workspacePath))
        {
            return [];
        }

        var projectDirectories = Directory
            .EnumerateFiles(repoRootPath, "*.csproj", new EnumerationOptions
            {
                RecurseSubdirectories = true,
                IgnoreInaccessible = true,
                AttributesToSkip = FileAttributes.ReparsePoint,
            })
            .Select(path => Path.GetDirectoryName(path)!)
            .Distinct(PathComparer.Instance)
            .Select(path => new DirectoryInfo(path))
            .ToImmutableArray();

        var fileBasedApps = new List<ProjectDiscoveryResult>();
        foreach (var csharpFilePath in Directory.EnumerateFiles(workspacePath, "*.cs", new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
        }).OrderBy(path => path, PathComparer.Instance))
        {
            if (IsInProjectCone(csharpFilePath, projectDirectories))
            {
                logger.Info($"    Excluding C# file [{csharpFilePath}] because it is under a C# project directory.");
                continue;
            }

            var relativeFilePath = Path.GetRelativePath(workspacePath, csharpFilePath).NormalizePathToUnix();
            var packageDependencies = GetPackageDependencies(csharpFilePath);
            if (packageDependencies.IsEmpty && !StartsWithShebang(csharpFilePath))
            {
                continue;
            }

            logger.Info($"    Discovered C# file-based app: {relativeFilePath}");
            fileBasedApps.Add(new ProjectDiscoveryResult
            {
                FilePath = relativeFilePath,
                TargetFrameworks = [DefaultTargetFramework],
                Dependencies = packageDependencies,
                ImportedFiles = [],
                AdditionalFiles = [],
                DependencyGraph = packageDependencies
                    .Where(d => d.Version is not null)
                    .ToImmutableDictionary(
                        d => $"{d.Name}/{d.Version}",
                        _ => ImmutableArray<string>.Empty,
                        StringComparer.OrdinalIgnoreCase),
            });
        }

        return [.. fileBasedApps];
    }

    internal static ImmutableArray<Dependency> GetPackageDependencies(string csharpFilePath)
    {
        var dependencies = new Dictionary<string, Dependency>(StringComparer.OrdinalIgnoreCase);
        var inBlockComment = false;
        foreach (var line in File.ReadLines(csharpFilePath))
        {
            var uncommentedLine = RemoveComments(line.TrimStart('\uFEFF'), ref inBlockComment);
            var match = PackageDirectiveRegex().Match(uncommentedLine);
            if (!match.Success)
            {
                continue;
            }

            var packageName = match.Groups["PackageName"].Value;
            var version = match.Groups["Version"].Success
                ? match.Groups["Version"].Value
                : null;
            dependencies.TryAdd(packageName, new Dependency(
                Name: packageName,
                Version: string.IsNullOrWhiteSpace(version) ? null : version,
                Type: DependencyType.PackageReference,
                TargetFrameworks: [DefaultTargetFramework]));
        }

        return [.. dependencies.Values.OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase)];
    }

    private static bool IsInProjectCone(string csharpFilePath, ImmutableArray<DirectoryInfo> projectDirectories)
    {
        var fileInfo = new FileInfo(csharpFilePath);
        return projectDirectories.Any(projectDirectory => PathHelper.IsFileUnderDirectory(projectDirectory, fileInfo));
    }

    private static bool StartsWithShebang(string csharpFilePath)
    {
        using var stream = File.OpenRead(csharpFilePath);
        Span<byte> buffer = stackalloc byte[5];
        var bytesRead = stream.Read(buffer);
        if (bytesRead >= 5 &&
            buffer[0] == 0xEF &&
            buffer[1] == 0xBB &&
            buffer[2] == 0xBF)
        {
            return buffer[3] == (byte)'#' && buffer[4] == (byte)'!';
        }

        return bytesRead >= 2 &&
            buffer[0] == (byte)'#' &&
            buffer[1] == (byte)'!';
    }

    private static string RemoveComments(string line, ref bool inBlockComment)
    {
        var remaining = line;
        var result = string.Empty;
        while (remaining.Length > 0)
        {
            if (inBlockComment)
            {
                var blockCommentEndIndex = remaining.IndexOf("*/", StringComparison.Ordinal);
                if (blockCommentEndIndex < 0)
                {
                    return result;
                }

                remaining = remaining[(blockCommentEndIndex + 2)..];
                inBlockComment = false;
                continue;
            }

            var lineCommentIndex = remaining.IndexOf("//", StringComparison.Ordinal);
            var blockCommentStartIndex = remaining.IndexOf("/*", StringComparison.Ordinal);
            if (lineCommentIndex >= 0 && (blockCommentStartIndex < 0 || lineCommentIndex < blockCommentStartIndex))
            {
                return result + remaining[..lineCommentIndex];
            }

            if (blockCommentStartIndex >= 0)
            {
                result += remaining[..blockCommentStartIndex];
                remaining = remaining[(blockCommentStartIndex + 2)..];
                inBlockComment = true;
                continue;
            }

            return result + remaining;
        }

        return result;
    }

    [GeneratedRegex(@"^\s*#:package\s+(?<PackageName>[^\s@]+)(?:@(?<Version>[^\s]+))?\s*$")]
    private static partial Regex PackageDirectiveRegex();
}
