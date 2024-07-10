using NuGet.Frameworks;

namespace NuGetUpdater.Core.FrameworkChecker;

public class CompatibilityChecker
{
    public static bool IsCompatible(string[] projectTfms, string[] packageTfms, Logger logger)
    {
        var projectFrameworks = projectTfms.Select(ParseFramework);
        var packageFrameworks = packageTfms.Select(ParseFramework);

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

        static NuGetFramework ParseFramework(string tfm)
        {
            var framework = NuGetFramework.Parse(tfm);
            if (framework.HasPlatform && framework.PlatformVersion != FrameworkConstants.EmptyVersion)
            {
                // Platform versions are not well supported by the FrameworkCompatibilityService. Make a best
                // effort by including just the platform.
                framework = new NuGetFramework(framework.Framework, framework.Version, framework.Platform, FrameworkConstants.EmptyVersion);
            }

            return framework;
        }
    }
}
