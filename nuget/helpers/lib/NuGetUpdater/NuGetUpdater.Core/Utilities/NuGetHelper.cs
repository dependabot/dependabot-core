using System.IO;

namespace NuGetUpdater.Core;

internal static class NuGetHelper
{
    internal const string PackagesConfigFileName = "packages.config";

    public static bool HasPackagesConfigFile(string projectPath)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);
        var packagesConfigPath = PathHelper.JoinPath(projectDirectory, PackagesConfigFileName);
        return File.Exists(packagesConfigPath);
    }
}
