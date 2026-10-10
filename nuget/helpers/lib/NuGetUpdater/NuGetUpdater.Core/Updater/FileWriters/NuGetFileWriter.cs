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

    public Task<bool> UpdatePackageVersionsAsync(
        DirectoryInfo repoContentsPath,
        ImmutableArray<string> relativeFilePaths,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> requiredPackageVersions,
        PackageManagementKind packageManagementKind,
        string? packageManagementSpecialFileRelativePath)
    {
        IFileWriter writer = relativeFilePaths.Any(CSharpFileBasedAppFileWriter.IsSupportedFilePath)
            ? _csharpFileBasedAppFileWriter
            : _xmlFileWriter;
        return writer.UpdatePackageVersionsAsync(
            repoContentsPath,
            relativeFilePaths,
            originalDependencies,
            requiredPackageVersions,
            packageManagementKind,
            packageManagementSpecialFileRelativePath);
    }
}
