using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;
using NuGetUpdater.Core.Run.ApiModel;
using NuGetUpdater.Core.Utilities;

using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Run;

public class ModifiedFilesTracker
{
    public readonly DirectoryInfo RepoContentsPath;
    private WorkspaceDiscoveryResult? _currentDiscoveryResult = null;
    private readonly ILogger _logger;

    private readonly Dictionary<string, string> _originalDependencyFileContents = [];
    private readonly Dictionary<string, EOLType> _originalDependencyFileEOFs = [];
    private readonly Dictionary<string, bool> _originalDependencyFileBOMs = [];
    private string[] _nonProjectFiles = [];
    private readonly HashSet<string> _initiallyExistingFiles;

    /// <summary>
    /// The set of file name patterns (case-insensitive) that are allowed to be edited during an update run.
    /// Files matching these patterns are tracked for pre-existence; any file not present before discovery
    /// will not be reported as modified.
    /// </summary>
    internal static readonly string[] AllowedEditableFilePatterns =
    [
        "global.json",
        "dotnet-tools.json",
        "*.csproj",
        "*.fsproj",
        "*.vbproj",
        "*.props",
        "*.targets",
        "app.config",
        "web.config",
        "packages.config",
        "packages.lock.json",
    ];

    public IReadOnlyDictionary<string, string> OriginalDependencyFileContents => _originalDependencyFileContents;
    //public IReadOnlyDictionary<string, EOLType> OriginalDependencyFileEOFs => _originalDependencyFileEOFs;
    public IReadOnlyDictionary<string, bool> OriginalDependencyFileBOMs => _originalDependencyFileBOMs;

    public ModifiedFilesTracker(DirectoryInfo repoContentsPath, HashSet<string> initiallyExistingFiles, ILogger logger)
    {
        RepoContentsPath = repoContentsPath;
        _initiallyExistingFiles = initiallyExistingFiles;
        _logger = logger;
    }

    /// <summary>
    /// Returns the set of editable file paths (relative to repo root, unix-style) that currently exist on disk
    /// and match the allowed editable file patterns.
    /// </summary>
    public static HashSet<string> GetInitiallyExistingFiles(DirectoryInfo repoContentsPath)
    {
        var result = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var file in Directory.EnumerateFiles(repoContentsPath.FullName, "*", SearchOption.AllDirectories))
        {
            var fileName = Path.GetFileName(file);
            if (MatchesAllowedEditablePattern(fileName))
            {
                result.Add(Path.GetRelativePath(repoContentsPath.FullName, file).NormalizePathToUnix());
            }
        }

        return result;
    }

    public async Task StartTrackingAsync(WorkspaceDiscoveryResult discoveryResult)
    {
        if (_currentDiscoveryResult is not null)
        {
            throw new InvalidOperationException("Already tracking modified files.");
        }

        _currentDiscoveryResult = discoveryResult;

        // track original contents for later handling
        async Task TrackOriginalContentsAsync(string directory, string fileName)
        {
            var repoFullPath = CorrectRepoRelativePathCasing(directory, fileName);
            var localFullPath = Path.Join(RepoContentsPath.FullName, repoFullPath);
            var content = await File.ReadAllTextAsync(localFullPath);
            var rawContent = await File.ReadAllBytesAsync(localFullPath);
            _originalDependencyFileContents[repoFullPath] = content;
            _originalDependencyFileEOFs[repoFullPath] = content.GetPredominantEOL();
            _originalDependencyFileBOMs[repoFullPath] = rawContent.HasBOM();
        }

        foreach (var project in _currentDiscoveryResult.Projects)
        {
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            if (IsFileNotInitiallyPresent(Path.Join(_currentDiscoveryResult.Path, project.FilePath).NormalizePathToUnix()))
            {
                continue;
            }

            await TrackOriginalContentsAsync(_currentDiscoveryResult.Path, project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFilePath = Path.Join(projectDirectory, extraFile);
                if (IsFileNotInitiallyPresent(Path.Join(_currentDiscoveryResult.Path, extraFilePath).NormalizePathToUnix()))
                {
                    continue;
                }

                await TrackOriginalContentsAsync(_currentDiscoveryResult.Path, extraFilePath);
            }
        }

        _nonProjectFiles = new[]
        {
            _currentDiscoveryResult.GlobalJson?.FilePath,
            _currentDiscoveryResult.DotNetToolsJson?.FilePath,
        }.Where(f => f is not null).Cast<string>()
         .Where(f => !IsFileNotInitiallyPresent(Path.Join(_currentDiscoveryResult.Path, f).NormalizePathToUnix()))
         .ToArray();
        foreach (var nonProjectFile in _nonProjectFiles)
        {
            await TrackOriginalContentsAsync(_currentDiscoveryResult.Path, nonProjectFile);
        }
    }

    public async Task<ImmutableArray<DependencyFile>> StopTrackingAsync(bool restoreOriginalContents = false)
    {
        if (_currentDiscoveryResult is null)
        {
            throw new InvalidOperationException("No discovery result to track.");
        }

        var updatedDependencyFiles = new Dictionary<string, DependencyFile>();
        async Task AddUpdatedFileIfDifferentAsync(string directory, string fileName)
        {
            var repoFullPath = CorrectRepoRelativePathCasing(directory, fileName);
            var localFullPath = Path.GetFullPath(Path.Join(RepoContentsPath.FullName, repoFullPath));
            var originalContent = _originalDependencyFileContents[repoFullPath];
            var updatedContent = await File.ReadAllTextAsync(localFullPath);

            updatedContent = updatedContent.SetEOL(_originalDependencyFileEOFs[repoFullPath]);
            var updatedRawContent = updatedContent.SetBOM(_originalDependencyFileBOMs[repoFullPath]);
            await File.WriteAllBytesAsync(localFullPath, updatedRawContent);

            if (updatedContent != originalContent)
            {
                var reportedContent = updatedContent;
                var encoding = "utf-8";
                if (_originalDependencyFileBOMs[repoFullPath])
                {
                    reportedContent = Convert.ToBase64String(updatedRawContent);
                    encoding = "base64";
                }

                updatedDependencyFiles[localFullPath] = new DependencyFile()
                {
                    Name = Path.GetFileName(repoFullPath),
                    Directory = Path.GetDirectoryName(repoFullPath)!.NormalizePathToUnix(),
                    Content = reportedContent,
                    ContentEncoding = encoding,
                };

                if (restoreOriginalContents)
                {
                    var originalRawContent = originalContent
                        .SetEOL(_originalDependencyFileEOFs[repoFullPath])
                        .SetBOM(_originalDependencyFileBOMs[repoFullPath]);
                    await File.WriteAllBytesAsync(localFullPath, originalRawContent);
                }
            }
        }

        foreach (var project in _currentDiscoveryResult.Projects)
        {
            if (IsFileNotInitiallyPresent(Path.Join(_currentDiscoveryResult.Path, project.FilePath).NormalizePathToUnix()))
            {
                continue;
            }

            await AddUpdatedFileIfDifferentAsync(_currentDiscoveryResult.Path, project.FilePath);
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFilePath = Path.Join(projectDirectory, extraFile);
                if (IsFileNotInitiallyPresent(Path.Join(_currentDiscoveryResult.Path, extraFilePath).NormalizePathToUnix()))
                {
                    continue;
                }

                await AddUpdatedFileIfDifferentAsync(_currentDiscoveryResult.Path, extraFilePath);
            }
        }

        foreach (var nonProjectFile in _nonProjectFiles)
        {
            await AddUpdatedFileIfDifferentAsync(_currentDiscoveryResult.Path, nonProjectFile);
        }

        _currentDiscoveryResult = null;

        var updatedDependencyFileList = updatedDependencyFiles
            .OrderBy(kvp => kvp.Key)
            .Select(kvp => kvp.Value)
            .ToImmutableArray();
        return updatedDependencyFileList;
    }

    private string CorrectRepoRelativePathCasing(string directory, string fileName)
    {
        var repoFullPath = Path.Join(directory, fileName).FullyNormalizedRootedPath();
        var correctedRepoFullPath = RunWorker.EnsureCorrectFileCasing(repoFullPath, RepoContentsPath.FullName, _logger);
        return correctedRepoFullPath;
    }

    private bool IsFileNotInitiallyPresent(string repoRelativePath)
    {
        return IsFileNotInitiallyPresent(repoRelativePath, _initiallyExistingFiles);
    }

    public static bool IsFileNotInitiallyPresent(string repoRelativePath, HashSet<string> initiallyExistingFiles)
    {
        var normalizedPath = repoRelativePath.NormalizePathToUnix().NormalizeUnixPathParts().TrimStart('/');
        var fileName = Path.GetFileName(normalizedPath);

        if (!MatchesAllowedEditablePattern(fileName))
        {
            return false;
        }

        return !initiallyExistingFiles.Contains(normalizedPath);
    }

    internal static bool MatchesAllowedEditablePattern(string fileName)
    {
        foreach (var pattern in AllowedEditableFilePatterns)
        {
            if (pattern.StartsWith("*"))
            {
                var extension = pattern[1..]; // e.g., ".csproj"
                if (fileName.EndsWith(extension, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
            else
            {
                if (fileName.Equals(pattern, StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }
        }

        return false;
    }

    public static ImmutableArray<DependencyFile> MergeUpdatedFileSet(ImmutableArray<DependencyFile> setA, ImmutableArray<DependencyFile> setB)
    {
        static string GetFullName(DependencyFile df) => Path.Join(df.Directory, df.Name).NormalizePathToUnix();
        var finalSet = setA.ToDictionary(GetFullName, df => df);
        foreach (var dependencyFile in setB)
        {
            finalSet[GetFullName(dependencyFile)] = dependencyFile;
        }

        return finalSet
            .OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase)
            .Select(kvp => kvp.Value)
            .ToImmutableArray();
    }
}
