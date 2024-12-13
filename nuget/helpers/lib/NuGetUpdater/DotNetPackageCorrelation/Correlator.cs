using System.Collections.Immutable;
using System.Text.Json;
using System.Text.RegularExpressions;

using Semver;

namespace DotNetPackageCorrelation;

public partial class Correlator
{
    internal static readonly JsonSerializerOptions SerializerOptions = new()
    {
        WriteIndented = true,
        Converters = { new SemVersionConverter() },
    };

    private readonly DirectoryInfo _releaseNotesDirectory;

    public Correlator(DirectoryInfo releaseNotesDirectory)
    {
        _releaseNotesDirectory = releaseNotesDirectory;
    }

    public async Task<(SdkPackages Packages, IEnumerable<string> Warnings)> RunAsync()
    {
        var runtimeVersions = new List<Version>();
        foreach (var directory in Directory.EnumerateDirectories(_releaseNotesDirectory.FullName))
        {
            var directoryName = Path.GetFileName(directory);
            if (Version.TryParse(directoryName, out var version))
            {
                runtimeVersions.Add(version);
            }
        }

        var sdkPackages = new SdkPackages();
        var warnings = new List<string>();
        foreach (var version in runtimeVersions)
        {
            var releasesJsonPath = Path.Combine(_releaseNotesDirectory.FullName, version.ToString(), "releases.json");
            if (!File.Exists(releasesJsonPath))
            {
                warnings.Add($"Unable to find releases.json file for version {version}");
                continue;
            }

            var releasesJson = await File.ReadAllTextAsync(releasesJsonPath);
            var releasesFile = JsonSerializer.Deserialize<ReleasesFile>(releasesJson, SerializerOptions)!; // TODO

            foreach (var release in releasesFile.Releases)
            {
                if (release.Sdk.Version is null)
                {
                    warnings.Add($"Skipping release with missing version information from {releasesJson}");
                    continue;
                }

                if (release.Sdk.RuntimeVersion is null)
                {
                    warnings.Add($"Skipping release with missing runtime version information from {releasesJson}");
                    continue;
                }

                if (!sdkPackages.Packages.TryGetValue(release.Sdk.Version, out var packagesAndVersions))
                {
                    packagesAndVersions = new PackageSet();
                    sdkPackages.Packages[release.Sdk.Version] = packagesAndVersions;
                }

                var runtimeDirectory = new DirectoryInfo(Path.Combine(_releaseNotesDirectory.FullName, version.ToString(), release.Sdk.RuntimeVersion.ToString()));
                var runtimeMarkdownPath = Path.Combine(runtimeDirectory.FullName, $"{release.Sdk.RuntimeVersion}.md");
                if (!File.Exists(runtimeMarkdownPath))
                {
                    warnings.Add($"Unable to find expected markdown file {runtimeMarkdownPath}");
                    continue;
                }

                var markdownContent = await File.ReadAllTextAsync(runtimeMarkdownPath);
                var packages = GetPackagesFromMarkdown(runtimeMarkdownPath, markdownContent, warnings);
                foreach (var (packageName, packageVersion) in packages)
                {
                    packagesAndVersions.Packages[packageName] = packageVersion;
                }
            }
        }

        return (sdkPackages, warnings);
    }

    public static ImmutableArray<(string Name, SemVersion Version)> GetPackagesFromMarkdown(string markdownPath, string markdownContent, List<string> warnings)
    {
        var lines = markdownContent.Split("\n").Select(l => l.Trim()).ToArray();

        // the markdown file contains a table that looks like this:
        //   Package name | Version
        //   :----------- | :------------------
        //   Some.Package | 1.2.3
        //   ...
        // however there are some formatting issues with some elements that prevent markdown parsers from
        // discovering it, so we fall back to manual parsing

        var tableStartLine = -1;
        for (int i = 0; i < lines.Length; i++)
        {
            if (Regex.IsMatch(lines[i], "Package name.*Version"))
            {
                tableStartLine = i;
                break;
            }
        }

        if (tableStartLine == -1)
        {
            warnings.Add($"Unable to find table start in file {markdownPath}");
            return [];
        }

        // skip the column names and separator line
        tableStartLine += 2;

        var tableEndLine = lines.Length; // assume the end of the file unless we find a blank line
        for (int i = tableStartLine; i < lines.Length; i++)
        {
            if (string.IsNullOrEmpty(lines[i]))
            {
                tableEndLine = i;
                break;
            }
        }

        var packages = new List<(string Name, SemVersion Version)>();
        for (int i = tableStartLine; i < tableEndLine; i++)
        {
            var line = lines[i].Trim();
            var foundMatch = false;
            foreach (var pattern in SpecialCasePatterns)
            {
                var match = pattern.Match(line);
                if (match.Success)
                {
                    var packageName = match.Groups["PackageName"].Value;
                    var packageVersionString = match.Groups["PackageVersion"].Value;
                    if (SemVersion.TryParse(packageVersionString, out var packageVersion))
                    {
                        packages.Add((packageName, packageVersion));
                        foundMatch = true;
                        break; ;
                    }
                }
            }

            if (!foundMatch)
            {
                warnings.Add($"Unable to parse package and version from string [{line}] in file [{markdownPath}]:{i}");
            }
        }

        return packages.ToImmutableArray();
    }

    // The different patterns the lines in the markdown might take.  Due to issues with regular expressions, this list
    // is in a very specific order.
    private static ImmutableArray<Regex> SpecialCasePatterns { get; } = [
        StandardLineWithFileExtensions(),
        StandardLine(),
        PackageNameDotVersion(),
        PackageFileNameWithOptionalTrailingPipe(),
        MultiColumnWithOptionalFileSuffix(),
    ];

    [GeneratedRegex(@"^(?<PackageName>[^|\s]+)\s*\|\s*(?<PackageVersion>[^|\s]+?)(\.symbols)?\.nupkg$", RegexOptions.Compiled)]
    // Some.Package | 1.2.3.nupkg
    // Some.Package | 1.2.3.symbols.nupkg
    private static partial Regex StandardLineWithFileExtensions();

    [GeneratedRegex(@"^(?<PackageName>[^|\s]+)\s*\|\s*(?<PackageVersion>[^|\s]+)$", RegexOptions.Compiled)]
    // Some.Package | 1.2.3
    private static partial Regex StandardLine();

    [GeneratedRegex(@"^(?<PackageName>[^\d]+)\.(?<PackageVersion>[\d].+)$", RegexOptions.Compiled)]
    // Some.Package.1.2.3
    private static partial Regex PackageNameDotVersion();

    [GeneratedRegex(@"^(?<PackageName>[^\d]+)\.(?<PackageVersion>\d.+?)\.nupkg(\s+\|)?$", RegexOptions.Compiled)]
    // some.package.1.2.3.nupkg
    // some.package.1.2.3.nupkg |
    private static partial Regex PackageFileNameWithOptionalTrailingPipe();

    [GeneratedRegex(@"^(?<PackageName>[^|\s]+)\s*\|[^|]*\|\s*(?<PackageVersion>.*?)(\.nupkg)?$", RegexOptions.Compiled)]
    // Some.Package | 1.2 | 1.2.3.nupkg
    private static partial Regex MultiColumnWithOptionalFileSuffix();
}
