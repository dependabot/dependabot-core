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

    internal static async Task<bool> DownloadNuGetPackagesAsync(string repoRoot, string projectPath, IReadOnlyCollection<Dependency> packages, Logger logger)
    {
        var tempDirectory = Directory.CreateTempSubdirectory("msbuild_sdk_restore_");
        try
        {
            var tempProjectPath = await MSBuildHelper.CreateTempProjectAsync(tempDirectory, repoRoot, projectPath, "netstandard2.0", packages, usePackageDownload: true);
            var (exitCode, stdOut, stdErr) = await ProcessEx.RunAsync("dotnet", $"restore \"{tempProjectPath}\"");

            return exitCode == 0;
        }
        finally
        {
            tempDirectory.Delete(recursive: true);
        }
    }
}
