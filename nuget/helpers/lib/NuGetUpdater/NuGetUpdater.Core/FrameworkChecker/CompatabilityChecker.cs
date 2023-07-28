using System.Linq;

using NuGet.Frameworks;

namespace NuGetUpdater.Core.FrameworkChecker;

public class CompatibilityChecker
{
    public static bool IsCompatible(string[] projectTfms, string[] packageTfms, Logger logger)
    {
        var projectFrameworks = projectTfms.Select(t => NuGetFramework.Parse(t));
        var packageFrameworks = packageTfms.Select(t => NuGetFramework.Parse(t));

        var compatibilityService = new FrameworkCompatibilityService();
        var compatibleFrameworks = compatibilityService.GetCompatibleFrameworks(packageFrameworks);

        var incompatibleFrameworks = projectFrameworks.Where(f => !compatibleFrameworks.Contains(f)).ToArray();
        if (incompatibleFrameworks.Length > 0)
        {
            logger.Log($"The package is not compatible. Incompatible project frameworks: {string.Join(", ", incompatibleFrameworks.Select(f => f.GetShortFolderName()))}");
            return false;
        }

        logger.Log("The package is compatible.");
        return true;
    }
}