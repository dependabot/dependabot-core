using System.Diagnostics.CodeAnalysis;

namespace NuGetUpdater.Core;

internal static class NuGetHelper
{
    internal const string PackagesConfigFileName = "packages.config";

    public static bool TryGetPackagesConfigFile(string projectPath, [NotNullWhen(returnValue: true)] out string? packagesConfigPath)
    {
        var projectDirectory = Path.GetDirectoryName(projectPath);

        packagesConfigPath = PathHelper.JoinPath(projectDirectory, PackagesConfigFileName);
        if (File.Exists(packagesConfigPath))
        {
            return true;
        }

        packagesConfigPath = null;
        return false;
    }
}
