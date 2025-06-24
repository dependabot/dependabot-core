// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using NuGet.Frameworks;

using NuGetGallery.Frameworks;

namespace NuGetUpdater.Core.FrameworkChecker;

public class FrameworkCompatibilityService
{
    private static readonly IFrameworkCompatibilityProvider CompatibilityProvider = DefaultCompatibilityProvider.Instance;
    private static readonly IReadOnlyList<NuGetFramework> AllSupportedFrameworks = SupportedFrameworks.AllSupportedNuGetFrameworks;
    private static readonly IReadOnlyDictionary<NuGetFramework, ISet<NuGetFramework>> CompatibilityMatrix = GetCompatibilityMatrix();

    public ISet<NuGetFramework> GetCompatibleFrameworks(IEnumerable<NuGetFramework>? packageFrameworks)
    {
        if (packageFrameworks == null)
        {
            throw new ArgumentNullException(nameof(packageFrameworks));
        }

        var allCompatibleFrameworks = new HashSet<NuGetFramework>();

        foreach (var packageFramework in packageFrameworks)
        {
            if (packageFrameworks == null || packageFramework.IsUnsupported)
            {
                continue;
            }

            if (CompatibilityMatrix.TryGetValue(packageFramework, out var compatibleFrameworks))
            {
                allCompatibleFrameworks.UnionWith(compatibleFrameworks);
            }
            else
            {
                allCompatibleFrameworks.Add(packageFramework);
            }
        }

        return allCompatibleFrameworks;
    }

    private static IReadOnlyDictionary<NuGetFramework, ISet<NuGetFramework>> GetCompatibilityMatrix()
    {
        var matrix = new Dictionary<NuGetFramework, ISet<NuGetFramework>>();

        foreach (var packageFramework in AllSupportedFrameworks)
        {
            var compatibleFrameworks = new HashSet<NuGetFramework>();
            matrix.Add(packageFramework, compatibleFrameworks);

            foreach (var projectFramework in AllSupportedFrameworks)
            {
                // This compatibility check is to know if the packageFramework can be installed on a certain projectFramework
                if (CompatibilityProvider.IsCompatible(projectFramework, packageFramework))
                {
                    compatibleFrameworks.Add(projectFramework);
                }
            }
        }

        // e.g., explicitly allow a project targeting `net9.0-windows` to consume packages targeting `net9.0-windows7.0`
        foreach (var packageFramework in SupportedFrameworks.TfmFilters.NetTfms)
        {
            if (packageFramework.Version.Major <= 5)
            {
                // the TFM `net5.0-windows7.0` isn't valid
                continue;
            }

            var packageFrameworkWithWindowsVersion = new NuGetFramework(packageFramework.Framework, packageFramework.Version, "windows", FrameworkConstants.Version7);
            var compatibleVersions = SupportedFrameworks.TfmFilters.NetTfms.Where(t => t.Version.Major >= packageFrameworkWithWindowsVersion.Version.Major).ToArray();
            foreach (var compatibleVersion in compatibleVersions)
            {
                var compatibleWindowsTargetWithoutVersion = new NuGetFramework(compatibleVersion.Framework, compatibleVersion.Version, "windows", FrameworkConstants.EmptyVersion);
                matrix[packageFrameworkWithWindowsVersion].Add(compatibleWindowsTargetWithoutVersion);
            }
        }

        // portable profiles
        var portableMappings = new DefaultPortableFrameworkMappings();
        var portableFrameworks = portableMappings.ProfileFrameworks.ToDictionary(p => p.Key, p => p.Value);
        foreach (var (profileNumber, frameworkRange) in portableMappings.CompatibilityMappings)
        {
            var profileFramework = new NuGetFramework(FrameworkConstants.FrameworkIdentifiers.Portable, new Version(0, 0, 0, 0), $"Profile{profileNumber}");
            var compatibleFrameworks = new HashSet<NuGetFramework>();
            matrix.Add(profileFramework, compatibleFrameworks);

            foreach (var packageFramework in AllSupportedFrameworks)
            {
                if (frameworkRange.Satisfies(packageFramework))
                {
                    foreach (var projectFramework in AllSupportedFrameworks)
                    {
                        if (CompatibilityProvider.IsCompatible(projectFramework, packageFramework))
                        {
                            compatibleFrameworks.Add(projectFramework);
                        }
                    }
                }
            }
        }

        return matrix;
    }
}
