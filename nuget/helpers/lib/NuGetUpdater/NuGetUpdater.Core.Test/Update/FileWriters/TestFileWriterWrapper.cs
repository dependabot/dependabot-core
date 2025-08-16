using System.Collections.Immutable;

using NuGetUpdater.Core.Updater.FileWriters;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

internal class TestFileWriterWrapper : IFileWriter
{
    public readonly Func<Task<bool>> UpdatePackageVersionsAsyncFunc;

    public TestFileWriterWrapper(Func<Task<bool>> updatePackageVersionsAsyncFunc)
    {
        UpdatePackageVersionsAsyncFunc = updatePackageVersionsAsyncFunc;
    }

    public Task<bool> UpdatePackageVersionsAsync(DirectoryInfo repoContentsPath, ImmutableArray<string> relativeFilePaths, ImmutableArray<Dependency> originalDependencies, ImmutableArray<Dependency> requiredPackageVersions, bool addPackageReferenceElementForPinnedPackages)
    {
        return UpdatePackageVersionsAsyncFunc();
    }

    public static TestFileWriterWrapper FromConstantResult(bool result)
    {
        return new TestFileWriterWrapper(() => Task.FromResult(result));
    }
}
