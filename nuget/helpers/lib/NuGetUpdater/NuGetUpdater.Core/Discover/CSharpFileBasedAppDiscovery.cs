using System.Collections.Immutable;
using System.Text.RegularExpressions;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

internal static partial class CSharpFileBasedAppDiscovery
{
    internal const string FileExtension = ".cs";

    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverAsync(string repoRootPath, string workspacePath, ILogger logger)
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

        var csharpFilePaths = Directory.EnumerateFiles(workspacePath, "*.cs", new EnumerationOptions
        {
            RecurseSubdirectories = true,
            IgnoreInaccessible = true,
            AttributesToSkip = FileAttributes.ReparsePoint,
        }).OrderBy(path => path, PathComparer.Instance).ToImmutableArray();
        if (csharpFilePaths.IsEmpty)
        {
            return [];
        }

        var targetFramework = await GetDefaultTargetFrameworkAsync(workspacePath, logger);

        var fileBasedApps = new List<ProjectDiscoveryResult>();
        foreach (var csharpFilePath in csharpFilePaths)
        {
            if (IsInProjectCone(csharpFilePath, projectDirectories))
            {
                logger.Info($"    Excluding C# file [{csharpFilePath}] because it is under a C# project directory.");
                continue;
            }

            var relativeFilePath = Path.GetRelativePath(workspacePath, csharpFilePath).NormalizePathToUnix();
            var packageDependencies = GetPackageDependencies(csharpFilePath, targetFramework);
            if (packageDependencies.IsEmpty && !StartsWithShebang(csharpFilePath))
            {
                continue;
            }

            var additionalFiles = ProjectHelper.GetAdditionalFilesFromProjectLocation(csharpFilePath, ProjectHelper.PathFormat.Relative);
            logger.Info($"    Discovered C# file-based app: {relativeFilePath}");
            fileBasedApps.Add(new ProjectDiscoveryResult
            {
                FilePath = relativeFilePath,
                TargetFrameworks = [targetFramework],
                Dependencies = packageDependencies,
                ImportedFiles = [],
                AdditionalFiles = additionalFiles,
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

    internal static ImmutableArray<Dependency> GetPackageDependencies(string csharpFilePath, string targetFramework)
    {
        var dependencies = new Dictionary<string, Dependency>(StringComparer.OrdinalIgnoreCase);
        var inBlockComment = false;
        foreach (var line in File.ReadLines(csharpFilePath))
        {
            if (!TryGetDirectiveBlockLine(line, ref inBlockComment, out var uncommentedLine))
            {
                break;
            }

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
                TargetFrameworks: [targetFramework]));
        }

        return [.. dependencies.Values.OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase)];
    }

    internal static bool IsDirectiveBlockLine(string line, ref bool inBlockComment)
        => TryGetDirectiveBlockLine(line, ref inBlockComment, out _);

    private static bool IsInProjectCone(string csharpFilePath, ImmutableArray<DirectoryInfo> projectDirectories)
    {
        var fileInfo = new FileInfo(csharpFilePath);
        return projectDirectories.Any(projectDirectory => PathHelper.IsFileUnderDirectory(projectDirectory, fileInfo));
    }

    internal static async Task<string> GetDefaultTargetFrameworkAsync(string workspacePath, ILogger logger)
    {
        var tempFilePath = Path.Combine(workspacePath, $".dependabot-target-framework-{Guid.NewGuid():N}.cs");
        await File.WriteAllTextAsync(tempFilePath, "Console.WriteLine();");
        try
        {
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(
                ["build", tempFilePath, "-getProperty:TargetFramework"],
                workspacePath);
            var targetFramework = GetTargetFrameworkFromOutput(stdOut);
            if (exitCode == 0 && targetFramework is not null)
            {
                return targetFramework;
            }

            logger.Warn($"Unable to determine the default target framework for C# file-based apps.\nSTDOUT:\n{stdOut}\nSTDERR:\n{stdErr}");
        }
        finally
        {
            File.Delete(tempFilePath);
        }

        return await GetDefaultTargetFrameworkFromSdkVersionAsync(workspacePath, logger);
    }

    private static string? GetTargetFrameworkFromOutput(string stdOut)
        => stdOut
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .LastOrDefault(line => line.StartsWith("net", StringComparison.OrdinalIgnoreCase));

    private static async Task<string> GetDefaultTargetFrameworkFromSdkVersionAsync(string workspacePath, ILogger logger)
    {
        var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["--version"], workspacePath);
        var match = SdkMajorVersionRegex().Match(stdOut);
        if (exitCode == 0 && match.Success)
        {
            var targetFramework = $"net{match.Groups["Major"].Value}.0";
            logger.Warn($"Falling back to default target framework {targetFramework} based on the .NET SDK version.");
            return targetFramework;
        }

        logger.Warn($"Unable to determine the .NET SDK version for C# file-based app target framework fallback.\nSTDOUT:\n{stdOut}\nSTDERR:\n{stdErr}");
        var runtimeTargetFramework = $"net{Environment.Version.Major}.0";
        logger.Warn($"Falling back to default target framework {runtimeTargetFramework} based on the current runtime version.");
        return runtimeTargetFramework;
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

    private static bool TryGetDirectiveBlockLine(string line, ref bool inBlockComment, out string uncommentedLine)
    {
        uncommentedLine = RemoveComments(line.TrimStart('\uFEFF'), ref inBlockComment);
        var trimmedLine = uncommentedLine.TrimStart();
        return trimmedLine.Length == 0 ||
            trimmedLine.StartsWith("#!", StringComparison.Ordinal) ||
            trimmedLine.StartsWith("#:", StringComparison.Ordinal);
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

    [GeneratedRegex(@"^\s*#:package\s+(?<PackageName>[^\s@]+)(?:@(?<Version>[^\s]+))?(?:\s+.*)?$")]
    private static partial Regex PackageDirectiveRegex();

    [GeneratedRegex(@"^(?<Major>\d+)\.")]
    private static partial Regex SdkMajorVersionRegex();
}
