using System.Collections.Immutable;
using System.Text;
using System.Text.RegularExpressions;

using NuGet.Versioning;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Updater.FileWriters;

public sealed partial class CSharpFileBasedAppFileWriter : IFileWriter
{
    public const string SupportedFileExtension = ".cs";

    private static readonly Encoding Utf8WithBom = new UTF8Encoding(encoderShouldEmitUTF8Identifier: true);
    private static readonly Encoding Utf8WithoutBom = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false);

    private readonly ILogger _logger;

    public CSharpFileBasedAppFileWriter(ILogger logger)
    {
        _logger = logger;
    }

    public async Task<bool> UpdatePackageVersionsAsync(
        DirectoryInfo repoContentsPath,
        ImmutableArray<string> relativeFilePaths,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> requiredPackageVersions,
        PackageManagementKind packageManagementKind)
    {
        var originalDependencyVersions = originalDependencies
            .Where(d => d.Version is not null && NuGetVersion.TryParse(d.Version, out _))
            .GroupBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => NuGetVersion.Parse(g.First().Version!), StringComparer.OrdinalIgnoreCase);
        var requiredDependencyVersions = requiredPackageVersions
            .Where(d => d.Version is not null)
            .GroupBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(g => g.Key, g => NuGetVersion.Parse(g.First().Version!), StringComparer.OrdinalIgnoreCase);

        var foundVersionedDirective = false;
        var allMatchedDirectivesUpdated = true;
        foreach (var relativeFilePath in relativeFilePaths.Where(IsSupportedFilePath))
        {
            var fullPath = Path.Join(repoContentsPath.FullName, relativeFilePath);
            var originalFile = await ReadTextFileAsync(fullPath);
            var updatedContents = UpdateFileContents(
                originalFile.Contents,
                originalDependencyVersions,
                requiredDependencyVersions,
                ref foundVersionedDirective,
                ref allMatchedDirectivesUpdated);
            if (updatedContents != originalFile.Contents)
            {
                await File.WriteAllTextAsync(fullPath, updatedContents, originalFile.Encoding);
            }
        }

        return foundVersionedDirective && allMatchedDirectivesUpdated;
    }

    public static bool IsSupportedFilePath(string filePath)
        => Path.GetExtension(filePath).Equals(SupportedFileExtension, StringComparison.OrdinalIgnoreCase);

    private string UpdateFileContents(
        string contents,
        IReadOnlyDictionary<string, NuGetVersion> originalDependencyVersions,
        IReadOnlyDictionary<string, NuGetVersion> requiredDependencyVersions,
        ref bool foundVersionedDirective,
        ref bool allMatchedDirectivesUpdated)
    {
        var updatedContents = new StringBuilder(contents.Length);
        foreach (Match lineMatch in LineRegex().Matches(contents))
        {
            if (lineMatch.Length == 0)
            {
                continue;
            }

            var line = lineMatch.Groups["Line"].Value;
            var eol = lineMatch.Groups["EndOfLine"].Value;
            var directiveMatch = PackageDirectiveRegex().Match(line);
            if (!directiveMatch.Success)
            {
                updatedContents.Append(line).Append(eol);
                continue;
            }

            var packageName = directiveMatch.Groups["PackageName"].Value;
            if (!originalDependencyVersions.TryGetValue(packageName, out var oldVersion) ||
                !requiredDependencyVersions.TryGetValue(packageName, out var requiredVersion))
            {
                updatedContents.Append(line).Append(eol);
                continue;
            }

            foundVersionedDirective = true;
            var versionText = directiveMatch.Groups["Version"].Value;
            if (!TryGetUpdatedVersion(versionText, oldVersion, requiredVersion, out var updatedVersion))
            {
                allMatchedDirectivesUpdated = false;
                _logger.Warn($"Unable to update C# file-based app package directive for {packageName} from version {versionText} to {requiredVersion}.");
                updatedContents.Append(line).Append(eol);
                continue;
            }

            var updatedLine = string.Concat(
                directiveMatch.Groups["Prefix"].Value,
                packageName,
                "@",
                updatedVersion,
                directiveMatch.Groups["Suffix"].Value);
            updatedContents.Append(updatedLine).Append(eol);
        }

        return updatedContents.ToString();
    }

    private static bool TryGetUpdatedVersion(string versionText, NuGetVersion oldVersion, NuGetVersion requiredVersion, out string updatedVersion)
    {
        if (NuGetVersion.TryParse(versionText, out var directiveVersion))
        {
            updatedVersion = directiveVersion == oldVersion
                ? requiredVersion.ToString()
                : versionText;
            return directiveVersion == oldVersion || directiveVersion >= requiredVersion;
        }

        if (VersionRange.TryParse(versionText, out var directiveVersionRange))
        {
            if (directiveVersionRange.Satisfies(oldVersion))
            {
                updatedVersion = XmlFileWriter.CreateUpdatedVersionRangeString(directiveVersionRange, oldVersion, requiredVersion);
                return true;
            }

            if (directiveVersionRange.Satisfies(requiredVersion))
            {
                updatedVersion = versionText;
                return true;
            }
        }

        updatedVersion = versionText;
        return false;
    }

    private static async Task<TextFileContents> ReadTextFileAsync(string fullPath)
    {
        var bytes = await File.ReadAllBytesAsync(fullPath);
        var hasUtf8Bom = bytes.AsSpan().StartsWith(Utf8WithBom.GetPreamble());
        using var stream = new MemoryStream(bytes);
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        var contents = await reader.ReadToEndAsync();
        var encoding = reader.CurrentEncoding.CodePage == Encoding.UTF8.CodePage
            ? hasUtf8Bom ? Utf8WithBom : Utf8WithoutBom
            : reader.CurrentEncoding;

        return new TextFileContents(contents, encoding);
    }

    [GeneratedRegex(@"(?<Line>[^\r\n]*)(?<EndOfLine>\r\n|\n|\r|$)")]
    private static partial Regex LineRegex();

    [GeneratedRegex(@"^(?<Prefix>\s*#:package\s+)(?<PackageName>[^\s@]+)@(?<Version>[^\s/]+)(?<Suffix>\s*(?://.*|/\*.*\*/\s*)?)$")]
    private static partial Regex PackageDirectiveRegex();

    private readonly record struct TextFileContents(string Contents, Encoding Encoding);
}
