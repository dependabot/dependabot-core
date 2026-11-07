namespace NuGetUpdater.Core;

public interface IGraphWorker
{
    Task<int> RunAsync(FileInfo jobFilePath, DirectoryInfo repoContentsPath, DirectoryInfo? caseInsensitiveRepoContentsPath, string baseCommitSha);
}
