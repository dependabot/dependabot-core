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

    private readonly Dictionary<string, string> _originalDependencyFileContents = [];
    private readonly Dictionary<string, EOLType> _originalDependencyFileEOFs = [];
    private readonly Dictionary<string, bool> _originalDependencyFileBOMs = [];
    private string[] _nonProjectFiles = [];

    public IReadOnlyDictionary<string, string> OriginalDependencyFileContents => _originalDependencyFileContents;
    //public IReadOnlyDictionary<string, EOLType> OriginalDependencyFileEOFs => _originalDependencyFileEOFs;
    public IReadOnlyDictionary<string, bool> OriginalDependencyFileBOMs => _originalDependencyFileBOMs;

    public ModifiedFilesTracker(DirectoryInfo repoContentsPath)
    {
        RepoContentsPath = repoContentsPath;
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
            var repoFullPath = Path.Join(directory, fileName).FullyNormalizedRootedPath();
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
            await TrackOriginalContentsAsync(_currentDiscoveryResult.Path, project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFilePath = Path.Join(projectDirectory, extraFile);
                await TrackOriginalContentsAsync(_currentDiscoveryResult.Path, extraFilePath);
            }
        }

        _nonProjectFiles = new[]
        {
            _currentDiscoveryResult.GlobalJson?.FilePath,
            _currentDiscoveryResult.DotNetToolsJson?.FilePath,
        }.Where(f => f is not null).Cast<string>().ToArray();
        foreach (var nonProjectFile in _nonProjectFiles)
        {
            await TrackOriginalContentsAsync(_currentDiscoveryResult.Path, nonProjectFile);
        }
    }

    public async Task<ImmutableArray<DependencyFile>> StopTrackingAsync()
    {
        if (_currentDiscoveryResult is null)
        {
            throw new InvalidOperationException("No discovery result to track.");
        }

        var updatedDependencyFiles = new Dictionary<string, DependencyFile>();
        async Task AddUpdatedFileIfDifferentAsync(string directory, string fileName)
        {
            var repoFullPath = Path.Join(directory, fileName).FullyNormalizedRootedPath();
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
            }
        }

        foreach (var project in _currentDiscoveryResult.Projects)
        {
            await AddUpdatedFileIfDifferentAsync(_currentDiscoveryResult.Path, project.FilePath);
            var projectDirectory = Path.GetDirectoryName(project.FilePath);
            foreach (var extraFile in project.ImportedFiles.Concat(project.AdditionalFiles))
            {
                var extraFilePath = Path.Join(projectDirectory, extraFile);
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
