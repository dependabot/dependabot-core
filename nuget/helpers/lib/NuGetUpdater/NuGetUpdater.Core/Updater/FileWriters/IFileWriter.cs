using System.Collections.Immutable;

namespace NuGetUpdater.Core.Updater.FileWriters;

public interface IFileWriter
{
    Task<bool> UpdatePackageVersionsAsync(
        DirectoryInfo repoContentsPath,
        ImmutableArray<string> relativeFilePaths,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> requiredPackageVersions,
        bool addPackageReferenceElementForPinnedPackages
    );
}
