using System.Collections.Immutable;

using Microsoft.Build.Construction;

namespace NuGetUpdater.Core.Utilities;

internal static class ProjectHelper
{
    public const string PackagesConfigFileName = "packages.config";
    public const string AppConfigFileName = "app.config";
    public const string WebConfigFileName = "web.config";
    public const string PackagesLockJsonFileName = "packages.lock.json";

    public enum PathFormat
    {
        Relative,
        Full,
    }

    public static ImmutableArray<string> GetAllAdditionalFilesFromProject(string repoRootPath, string fullProjectPath, PathFormat pathFormat)
    {
        return GetAdditionalFilesFromProjectContent(repoRootPath, fullProjectPath, pathFormat)
            .Concat(GetAdditionalFilesFromProjectLocation(fullProjectPath, pathFormat))
            .OrderBy(p => p, StringComparer.Ordinal)
            .ToImmutableArray();
    }

    public static ImmutableArray<string> GetAdditionalFilesFromProjectContent(string repoRootPath, string fullProjectPath, PathFormat pathFormat)
    {
        var projectRootElement = ProjectRootElement.Open(fullProjectPath);
        var additionalFilesWithFullPaths = new[]
        {
            projectRootElement.GetItemPathWithFileName(repoRootPath, PackagesConfigFileName),
            projectRootElement.GetItemPathWithFileName(repoRootPath, AppConfigFileName),
            projectRootElement.GetItemPathWithFileName(repoRootPath, WebConfigFileName),
        }.Where(p => p is not null).Cast<string>().ToImmutableArray();

        var additionalFiles = additionalFilesWithFullPaths
            .Select(p => MakePathAppropriateFormat(fullProjectPath, p, pathFormat))
            .ToImmutableArray();
        return additionalFiles;
    }

    public static ImmutableArray<string> GetAdditionalFilesFromProjectLocation(string fullProjectPath, PathFormat pathFormat)
    {
        var additionalFilesWithFullPaths = new[]
        {
            GetPathWithRegardsToProjectFile(fullProjectPath, PackagesLockJsonFileName),
        }.Where(p => p is not null).Cast<string>().ToImmutableArray();

        var additionalFiles = additionalFilesWithFullPaths
            .Select(p => MakePathAppropriateFormat(fullProjectPath, p, pathFormat))
            .ToImmutableArray();
        return additionalFiles;
    }

    public static string? GetPackagesConfigPathFromProject(string repoRootPath, string fullProjectPath, PathFormat pathFormat)
    {
        var additionalFiles = GetAdditionalFilesFromProjectContent(repoRootPath, fullProjectPath, pathFormat);
        var packagesConfigFile = additionalFiles.FirstOrDefault(p => Path.GetFileName(p).Equals(PackagesConfigFileName, StringComparison.OrdinalIgnoreCase));
        return packagesConfigFile;
    }

    private static string MakePathAppropriateFormat(string fullProjectPath, string fullFilePath, PathFormat pathFormat)
    {
        var projectDirectory = Path.GetDirectoryName(fullProjectPath)!;
        var updatedPath = pathFormat switch
        {
            PathFormat.Full => fullFilePath,
            PathFormat.Relative => Path.GetRelativePath(projectDirectory, fullFilePath),
            _ => throw new NotSupportedException(),
        };
        return updatedPath.NormalizePathToUnix();
    }

    private static string? GetItemPathWithFileName(this ProjectRootElement projectRootElement, string repoRootPath, string itemFileName)
    {
        var projectDirectory = Path.GetDirectoryName(projectRootElement.FullPath)!;
        var itemPath = projectRootElement.Items
            .Where(i => i.ElementName.Equals("None", StringComparison.OrdinalIgnoreCase) ||
                        i.ElementName.Equals("Content", StringComparison.OrdinalIgnoreCase))
            .Where(i => !string.IsNullOrEmpty(i.Include))
            .Select(i => Path.GetFullPath(Path.Combine(projectDirectory, i.Include.NormalizePathToUnix())))
            .Where(p => Path.GetFileName(p).Equals(itemFileName, StringComparison.OrdinalIgnoreCase))
            .Select(p =>
            {
                var candidateFiles = PathHelper.ResolveCaseInsensitivePathsInsideRepoRoot(p, repoRootPath) ?? []; // case correct
                if (candidateFiles.Count == 1)
                {
                    return candidateFiles[0];
                }

                return null;
            })
            .Where(p => p is not null)
            .FirstOrDefault();
        return itemPath;
    }

    private static string? GetPathWithRegardsToProjectFile(string fullProjectPath, string fileName)
    {
        var projectDirectory = Path.GetDirectoryName(fullProjectPath)!;
        var filePath = Directory.EnumerateFiles(projectDirectory)
            .Where(p => Path.GetFileName(p).Equals(fileName, StringComparison.OrdinalIgnoreCase))
            .FirstOrDefault();
        return filePath;
    }
}
