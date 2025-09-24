using System.Collections.Immutable;

using NuGetUpdater.Core.Updater.FileWriters;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

internal class TestFileWriterReturnsConstantResult : IFileWriter
{
    public bool Result { get; }

    public TestFileWriterReturnsConstantResult(bool result)
    {
        Result = result;
    }

    public Task<bool> UpdatePackageVersionsAsync(DirectoryInfo repoContentsPath, ImmutableArray<string> relativeFilePaths, ImmutableArray<Dependency> originalDependencies, ImmutableArray<Dependency> requiredPackageVersions, bool addPackageReferenceElementForPinnedPackages)
    {
        return Task.FromResult(Result);
    }
}
