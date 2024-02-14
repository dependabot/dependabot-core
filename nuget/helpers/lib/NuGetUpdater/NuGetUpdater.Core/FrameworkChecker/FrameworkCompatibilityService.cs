// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Generic;

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
            if (packageFrameworks == null || packageFramework.IsUnsupported || packageFramework.IsPCL)
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

        matrix.Add(
            SupportedFrameworks.Net60Windows7,
            new HashSet<NuGetFramework>
            {
                SupportedFrameworks.Net60Windows, SupportedFrameworks.Net60Windows7,
                SupportedFrameworks.Net70Windows, SupportedFrameworks.Net70Windows7
            }
        );

        return matrix;
    }
}
