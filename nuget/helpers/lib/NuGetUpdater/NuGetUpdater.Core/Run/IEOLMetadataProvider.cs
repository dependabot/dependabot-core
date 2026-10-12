using static NuGetUpdater.Core.Utilities.EOLHandling;

namespace NuGetUpdater.Core.Run;

internal interface IEOLMetadataProvider
{
    Task<Dictionary<string, EOLType>> GetIndexEOLsAsync(
        DirectoryInfo repoContentsPath,
        IReadOnlyCollection<string> repoRelativePaths);
}
