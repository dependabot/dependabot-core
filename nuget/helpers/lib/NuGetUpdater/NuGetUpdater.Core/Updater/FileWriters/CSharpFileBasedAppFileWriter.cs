using System.Collections.Immutable;
using System.Xml.Linq;

using Microsoft.CodeAnalysis.Text;

using NuGet.Versioning;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Updater.FileWriters;

public sealed class CSharpFileBasedAppFileWriter : IFileWriter
{
    public const string SupportedFileExtension = ".cs";

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
        PackageManagementKind packageManagementKind,
        string? packageManagementSpecialFileRelativePath)
    {
        var csharpFilePaths = relativeFilePaths.Where(IsSupportedFilePath).ToImmutableArray();
        if (csharpFilePaths.Length != 1)
        {
            _logger.Warn($"Expected one C# file-based app to update, but found {csharpFilePaths.Length}.");
            return false;
        }

        if (!TryGetRequiredDependencyVersions(requiredPackageVersions, out var requiredDependencyVersions) ||
            requiredDependencyVersions.Count == 0)
        {
            return false;
        }

        var originalDependencyVersions = GetParsedDependencyVersions(originalDependencies);

        var fullPath = Path.Join(repoContentsPath.FullName, csharpFilePaths[0]);
        var originalContents = await File.ReadAllTextAsync(fullPath);
        var syntax = CSharpFileBasedAppDiscovery.Parse(originalContents);
        if (syntax.PackageDirectives.IsEmpty)
        {
            _logger.Warn($"No package directives found in C# file-based app {csharpFilePaths[0]}.");
            return false;
        }

        if (packageManagementKind is PackageManagementKind.CentralPackageManagement or PackageManagementKind.CentralPackageManagementWithTransitivePinning)
        {
            return await UpdateCentralPackageVersionsAsync(
                repoContentsPath, relativeFilePaths, csharpFilePaths[0], originalContents, syntax.PackageDirectives,
                originalDependencies, requiredPackageVersions, requiredDependencyVersions,
                packageManagementKind, packageManagementSpecialFileRelativePath);
        }

        var changes = new List<TextChange>();
        var representedDependencies = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var directive in syntax.PackageDirectives)
        {
            if (!requiredDependencyVersions.TryGetValue(directive.Name, out var requiredVersion))
            {
                continue;
            }

            if (directive.Version is null)
            {
                if (!originalDependencyVersions.TryGetValue(directive.Name, out var previousVersion) || previousVersion != requiredVersion)
                {
                    changes.Add(new TextChange(new TextSpan(directive.NameSpan.End, 0), $"@{requiredVersion}"));
                }

                representedDependencies.Add(directive.Name);
                continue;
            }

            if (directive.VersionSpan is null ||
                !originalDependencyVersions.TryGetValue(directive.Name, out var oldVersion) ||
                !TryGetUpdatedVersion(directive.Version, oldVersion, requiredVersion, out var updatedVersion))
            {
                _logger.Warn($"Unable to update C# file-based app package directive for {directive.Name} to {requiredVersion}.");
                return false;
            }

            if (updatedVersion != directive.Version)
            {
                changes.Add(new TextChange(directive.VersionSpan.Value, updatedVersion));
            }

            representedDependencies.Add(directive.Name);
        }

        var missingDependencies = requiredDependencyVersions
            .Where(kvp => !representedDependencies.Contains(kvp.Key))
            .OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase)
            .ToImmutableArray();
        if (!missingDependencies.IsEmpty)
        {
            changes.Add(CreateMissingDirectivesChange(originalContents, syntax.PackageDirectives, missingDependencies));
        }

        var updatedContents = SourceText.From(originalContents).WithChanges(changes).ToString();
        if (updatedContents != originalContents)
        {
            await File.WriteAllTextAsync(fullPath, updatedContents);
        }

        return true;
    }

    public static bool IsSupportedFilePath(string filePath)
        => Path.GetExtension(filePath).Equals(SupportedFileExtension, StringComparison.OrdinalIgnoreCase);

    private async Task<bool> UpdateCentralPackageVersionsAsync(
        DirectoryInfo repoContentsPath,
        ImmutableArray<string> relativeFilePaths,
        string csharpFilePath,
        string originalContents,
        ImmutableArray<CSharpFileBasedAppPackageDirective> directives,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> requiredPackageVersions,
        IReadOnlyDictionary<string, NuGetVersion> requiredDependencyVersions,
        PackageManagementKind packageManagementKind,
        string? packageManagementSpecialFileRelativePath)
    {
        var references = directives.Select(d => new Dependency(d.Name, d.Version, DependencyType.PackageReference));
        var project = new XElement("Project", CSharpFileBasedAppDiscovery.CreatePackageReferences(references));
        var xmlWriter = new XmlFileWriter(_logger);
        var updatedFiles = await xmlWriter.UpdatePackageVersionsInMemoryAsync(
            repoContentsPath,
            [csharpFilePath, .. relativeFilePaths.Where(path => path != csharpFilePath)],
            originalDependencies,
            requiredPackageVersions,
            packageManagementKind,
            packageManagementSpecialFileRelativePath,
            project.ToString());
        if (updatedFiles is null)
        {
            return false;
        }

        var updatedProject = XElement.Parse(updatedFiles[csharpFilePath].ToFullString());
        var updatedReferences = updatedProject.Descendants("PackageReference").ToArray();
        if (updatedReferences.Any(r => r.Attribute("Version") is not null || r.Attribute("VersionOverride") is not null))
        {
            _logger.Warn($"Unable to write explicit package versions in centrally managed C# file-based app {csharpFilePath}.");
            return false;
        }

        var originalNames = directives.Select(d => d.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var addedNames = updatedReferences.Select(r => (string?)r.Attribute("Include"))
            .Where(name => name is not null && !originalNames.Contains(name))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var addedDependencies = requiredDependencyVersions
            .Where(kvp => addedNames.Contains(kvp.Key))
            .OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase)
            .ToImmutableArray();
        var updatedContents = addedDependencies.IsEmpty
            ? originalContents
            : SourceText.From(originalContents).WithChanges(
                CreateMissingDirectivesChange(originalContents, directives, addedDependencies, includeVersions: false)).ToString();

        foreach (var (path, document) in updatedFiles.Where(kvp => kvp.Key != csharpFilePath))
        {
            await XmlFileWriter.WriteFileContentsAsync(repoContentsPath, path, document);
        }

        if (updatedContents != originalContents)
        {
            await File.WriteAllTextAsync(Path.Join(repoContentsPath.FullName, csharpFilePath), updatedContents);
        }

        return true;
    }

    private bool TryGetRequiredDependencyVersions(
        ImmutableArray<Dependency> dependencies,
        out IReadOnlyDictionary<string, NuGetVersion> versions)
    {
        var parsedVersions = new Dictionary<string, NuGetVersion>(StringComparer.OrdinalIgnoreCase);
        foreach (var dependency in dependencies)
        {
            if (dependency.Version is null || !NuGetVersion.TryParse(dependency.Version, out var version))
            {
                _logger.Warn($"Unable to parse required dependency version for {dependency.Name}: {dependency.Version}.");
                versions = parsedVersions;
                return false;
            }

            parsedVersions.TryAdd(dependency.Name, version);
        }

        versions = parsedVersions;
        return true;
    }

    private static IReadOnlyDictionary<string, NuGetVersion> GetParsedDependencyVersions(
        ImmutableArray<Dependency> dependencies)
    {
        var parsedVersions = new Dictionary<string, NuGetVersion>(StringComparer.OrdinalIgnoreCase);
        foreach (var dependency in dependencies)
        {
            if (dependency.Version is not null && NuGetVersion.TryParse(dependency.Version, out var version))
            {
                parsedVersions.TryAdd(dependency.Name, version);
            }
        }

        return parsedVersions;
    }

    private static TextChange CreateMissingDirectivesChange(
        string contents,
        ImmutableArray<CSharpFileBasedAppPackageDirective> packageDirectives,
        ImmutableArray<KeyValuePair<string, NuGetVersion>> missingDependencies,
        bool includeVersions = true)
    {
        var sourceText = SourceText.From(contents);
        var lastDirective = packageDirectives.OrderBy(d => d.LineSpan.End).Last();
        var line = sourceText.Lines.GetLineFromPosition(lastDirective.LineSpan.Start);
        var hasLineBreak = line.EndIncludingLineBreak > line.End;
        var endOfLine = hasLineBreak
            ? sourceText.ToString(TextSpan.FromBounds(line.End, line.EndIncludingLineBreak))
            : GetFirstEndOfLine(sourceText) ?? "\n";
        var insertionPosition = line.EndIncludingLineBreak;
        var insertedLines = missingDependencies
            .Select(kvp => $"{lastDirective.Indentation}#:package {kvp.Key}{(includeVersions ? $"@{kvp.Value}" : string.Empty)}");
        var insertion = string.Concat(
            hasLineBreak ? string.Empty : endOfLine,
            string.Join(endOfLine, insertedLines),
            hasLineBreak ? endOfLine : string.Empty);
        return new TextChange(new TextSpan(insertionPosition, 0), insertion);
    }

    private static string? GetFirstEndOfLine(SourceText sourceText)
    {
        foreach (var line in sourceText.Lines)
        {
            if (line.EndIncludingLineBreak > line.End)
            {
                return sourceText.ToString(TextSpan.FromBounds(line.End, line.EndIncludingLineBreak));
            }
        }

        return null;
    }

    private static bool TryGetUpdatedVersion(
        string versionText,
        NuGetVersion oldVersion,
        NuGetVersion requiredVersion,
        out string updatedVersion)
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
}
