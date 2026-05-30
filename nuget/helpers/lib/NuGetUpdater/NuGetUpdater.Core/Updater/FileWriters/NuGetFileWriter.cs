using System.Collections.Immutable;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Updater.FileWriters;

public sealed class NuGetFileWriter : IFileWriter
{
    private readonly XmlFileWriter _xmlFileWriter;
    private readonly CSharpFileBasedAppFileWriter _csharpFileBasedAppFileWriter;

    public NuGetFileWriter(ILogger logger)
    {
        _xmlFileWriter = new XmlFileWriter(logger);
        _csharpFileBasedAppFileWriter = new CSharpFileBasedAppFileWriter(logger);
    }

    public async Task<bool> UpdatePackageVersionsAsync(
        DirectoryInfo repoContentsPath,
        ImmutableArray<string> relativeFilePaths,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> requiredPackageVersions,
        PackageManagementKind packageManagementKind)
    {
        var csharpFilePaths = relativeFilePaths
            .Where(CSharpFileBasedAppFileWriter.IsSupportedFilePath)
            .ToImmutableArray();
        var xmlFilePaths = relativeFilePaths
            .Where(path => !CSharpFileBasedAppFileWriter.IsSupportedFilePath(path))
            .ToImmutableArray();

        var succeeded = true;
        if (xmlFilePaths.Length > 0)
        {
            succeeded &= await _xmlFileWriter.UpdatePackageVersionsAsync(
                repoContentsPath,
                xmlFilePaths,
                originalDependencies,
                requiredPackageVersions,
                packageManagementKind);
        }

        if (csharpFilePaths.Length > 0)
        {
            succeeded &= await _csharpFileBasedAppFileWriter.UpdatePackageVersionsAsync(
                repoContentsPath,
                csharpFilePaths,
                originalDependencies,
                requiredPackageVersions,
                packageManagementKind);
        }

        return succeeded;
    }
}
