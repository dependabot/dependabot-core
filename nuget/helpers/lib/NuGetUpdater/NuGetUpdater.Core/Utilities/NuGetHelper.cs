using System.Diagnostics.CodeAnalysis;

namespace NuGetUpdater.Core;

internal static class NuGetHelper
{
    internal const string PackagesConfigFileName = "packages.config";

    public static bool HasPackagesConfigFile(string projectPath, [NotNullWhen(returnValue: true)] out string? packagesConfigPath)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);
        packagesConfigPath = PathHelper.JoinPath(projectDirectory, PackagesConfigFileName);
        return File.Exists(packagesConfigPath);
    }
}
