using System.Collections.Immutable;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Text;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

internal static class CSharpFileBasedAppDiscovery
{
    internal const string FileExtension = ".cs";

    public static async Task<ImmutableArray<ProjectDiscoveryResult>> DiscoverAsync(
        string repoRootPath,
        string workspacePath,
        ExperimentsManager experimentsManager,
        ILogger logger)
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

            var contents = await File.ReadAllTextAsync(csharpFilePath);
            var syntax = Parse(contents);
            if (!syntax.IsFileBasedApp)
            {
                continue;
            }

            var relativeFilePath = Path.GetRelativePath(workspacePath, csharpFilePath).NormalizePathToUnix();
            var topLevelDependencies = syntax.PackageDirectives
                .DistinctBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
                .Select(d => new Dependency(
                    Name: d.Name,
                    Version: d.Version ?? "*",
                    Type: DependencyType.PackageReference,
                    TargetFrameworks: [targetFramework]))
                .OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
                .ToImmutableArray();

            ProjectDiscoveryResult? resolvedProject = null;
            if (!topLevelDependencies.IsEmpty)
            {
                resolvedProject = await ResolveDependenciesAsync(
                    repoRootPath,
                    csharpFilePath,
                    targetFramework,
                    topLevelDependencies,
                    experimentsManager,
                    logger);
            }

            var additionalFiles = ProjectHelper.GetAdditionalFilesFromProjectLocation(csharpFilePath, ProjectHelper.PathFormat.Relative);
            logger.Info($"    Discovered C# file-based app: {relativeFilePath}");
            fileBasedApps.Add(new ProjectDiscoveryResult
            {
                FilePath = relativeFilePath,
                TargetFrameworks = resolvedProject?.TargetFrameworks ?? [targetFramework],
                Dependencies = resolvedProject?.Dependencies ?? [],
                ImportedFiles = [],
                AdditionalFiles = additionalFiles,
                DependencyGraph = resolvedProject?.DependencyGraph ??
                    ImmutableDictionary<string, ImmutableArray<string>>.Empty.WithComparers(StringComparer.OrdinalIgnoreCase),
            });
        }

        return [.. fileBasedApps];
    }

    internal static CSharpFileBasedAppSyntax Parse(string contents)
    {
        var sourceText = SourceText.From(contents);
        var syntaxTree = CSharpSyntaxTree.ParseText(
            sourceText,
            CSharpParseOptions.Default.WithLanguageVersion(LanguageVersion.Preview));
        var root = syntaxTree.GetRoot();
        var leadingTrivia = root.GetFirstToken(includeZeroWidth: true).LeadingTrivia;
        var isFileBasedApp = leadingTrivia.Any(t =>
            t.IsKind(SyntaxKind.IgnoredDirectiveTrivia) ||
            t.IsKind(SyntaxKind.ShebangDirectiveTrivia));

        var packageDirectives = leadingTrivia
            .Where(t => t.IsKind(SyntaxKind.IgnoredDirectiveTrivia))
            .Select(t => t.GetStructure())
            .OfType<IgnoredDirectiveTriviaSyntax>()
            .Select(d => TryParsePackageDirective(sourceText, d))
            .Where(d => d is not null)
            .Select(d => d!.Value)
            .ToImmutableArray();

        return new CSharpFileBasedAppSyntax(isFileBasedApp, packageDirectives);
    }

    private static async Task<ProjectDiscoveryResult> ResolveDependenciesAsync(
        string repoRootPath,
        string csharpFilePath,
        string targetFramework,
        ImmutableArray<Dependency> topLevelDependencies,
        ExperimentsManager experimentsManager,
        ILogger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("file_based_app_discovery_");
        try
        {
            var tempProjectPath = await MSBuildHelper.CreateTempProjectAsync(
                tempDirectory,
                repoRootPath,
                csharpFilePath,
                targetFramework,
                topLevelDependencies,
                logger,
                importDependencyTargets: false);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(
                ["restore", tempProjectPath],
                tempDirectory.FullName);
            if (exitCode != 0)
            {
                throw new InvalidOperationException(
                    $"Unable to restore temporary project for C# file-based app {csharpFilePath}." +
                    $"\nSTDOUT:\n{stdOut}\nSTDERR:\n{stdErr}");
            }

            var projects = await SdkProjectDiscovery.DiscoverAsync(
                repoRootPath,
                tempDirectory.FullName,
                tempProjectPath,
                experimentsManager,
                solutionDir: null,
                logger);
            if (projects.Length != 1)
            {
                throw new InvalidOperationException(
                    $"Unable to resolve C# file-based app dependencies for {csharpFilePath}. " +
                    $"Expected one temporary project result, but found [{string.Join(", ", projects.Select(p => p.FilePath))}].");
            }

            return projects[0];
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }

    private static CSharpFileBasedAppPackageDirective? TryParsePackageDirective(
        SourceText sourceText,
        IgnoredDirectiveTriviaSyntax directive)
    {
        var contentText = directive.Content.Text;
        var content = contentText.AsSpan();
        var index = 0;
        SkipWhitespace(content, ref index);

        const string packageKeyword = "package";
        if (!content[index..].StartsWith(packageKeyword, StringComparison.Ordinal))
        {
            return null;
        }

        index += packageKeyword.Length;
        if (index >= content.Length || !char.IsWhiteSpace(content[index]))
        {
            return null;
        }

        SkipWhitespace(content, ref index);
        var nameStart = index;
        while (index < content.Length && !char.IsWhiteSpace(content[index]) && content[index] != '@')
        {
            index++;
        }

        if (index == nameStart)
        {
            return null;
        }

        var name = content[nameStart..index].ToString();
        var nameSpan = new TextSpan(directive.Content.Span.Start + nameStart, index - nameStart);
        string? version = null;
        TextSpan? versionSpan = null;
        if (index < content.Length && content[index] == '@')
        {
            index++;
            var versionStart = index;
            while (index < content.Length && !char.IsWhiteSpace(content[index]))
            {
                index++;
            }

            if (index > versionStart)
            {
                version = content[versionStart..index].ToString();
                versionSpan = new TextSpan(directive.Content.Span.Start + versionStart, index - versionStart);
            }
        }

        var line = sourceText.Lines.GetLineFromPosition(directive.FullSpan.Start);
        var indentation = sourceText.ToString(TextSpan.FromBounds(line.Start, directive.HashToken.SpanStart));
        return new CSharpFileBasedAppPackageDirective(name, version, nameSpan, versionSpan, line.SpanIncludingLineBreak, indentation);
    }

    private static void SkipWhitespace(ReadOnlySpan<char> value, ref int index)
    {
        while (index < value.Length && char.IsWhiteSpace(value[index]))
        {
            index++;
        }
    }

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
        var versionText = stdOut.Trim();
        var separatorIndex = versionText.IndexOf('.');
        if (exitCode == 0 &&
            separatorIndex > 0 &&
            int.TryParse(versionText.AsSpan(0, separatorIndex), out var majorVersion))
        {
            var targetFramework = $"net{majorVersion}.0";
            logger.Warn($"Falling back to default target framework {targetFramework} based on the .NET SDK version.");
            return targetFramework;
        }

        logger.Warn($"Unable to determine the .NET SDK version for C# file-based app target framework fallback.\nSTDOUT:\n{stdOut}\nSTDERR:\n{stdErr}");
        var runtimeTargetFramework = $"net{Environment.Version.Major}.0";
        logger.Warn($"Falling back to default target framework {runtimeTargetFramework} based on the current runtime version.");
        return runtimeTargetFramework;
    }
}

internal readonly record struct CSharpFileBasedAppSyntax(
    bool IsFileBasedApp,
    ImmutableArray<CSharpFileBasedAppPackageDirective> PackageDirectives);

internal readonly record struct CSharpFileBasedAppPackageDirective(
    string Name,
    string? Version,
    TextSpan NameSpan,
    TextSpan? VersionSpan,
    TextSpan LineSpan,
    string Indentation);
