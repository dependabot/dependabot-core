// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System.Collections.Generic;
using System.Linq;

using NuGet.Frameworks;

using NuGetGallery.Frameworks;

using Xunit;

using static NuGet.Frameworks.FrameworkConstants;
using static NuGet.Frameworks.FrameworkConstants.CommonFrameworks;

namespace NuGetUpdater.Core.Test.FrameworkChecker;

public class SupportedFrameworksFacts
{
    private static readonly NuGetFramework Win = new NuGetFramework(FrameworkIdentifiers.Windows, EmptyVersion);
    private static readonly NuGetFramework WinRt = new NuGetFramework(FrameworkIdentifiers.WinRT, EmptyVersion);

    // See: https://docs.microsoft.com/en-us/dotnet/standard/frameworks#deprecated-target-frameworks
    private readonly HashSet<NuGetFramework> DeprecatedFrameworks = new HashSet<NuGetFramework>() {
            AspNet, AspNet50, AspNetCore, AspNetCore50,
            Dnx, Dnx45, Dnx451, Dnx452, DnxCore, DnxCore50,
            DotNet, DotNet50, DotNet51, DotNet52, DotNet53, DotNet54, DotNet55, DotNet56,
            NetCore50,
            Win, Win8, Win81, Win10,
            WinRt
        };
    // The following frameworks were included in NuGet.Client code but they were not official framework releases.
    private readonly HashSet<NuGetFramework> UnofficialFrameworks = new HashSet<NuGetFramework>()
        {
            NetStandard17, NetStandardApp15
        };

    [Fact]
    public void SupportedFrameworksContainsCommonFrameworksWithNoDeprecatedFrameworks()
    {
        var fields = typeof(FrameworkConstants.CommonFrameworks)
            .GetFields()
            .Where(f => f.FieldType == typeof(NuGetFramework))
            .ToList();

        Assert.True(fields.Count > 0);

        var supportedFrameworks = new HashSet<NuGetFramework>(SupportedFrameworks.AllSupportedNuGetFrameworks);

        foreach (var field in fields)
        {
            var framework = (NuGetFramework)field.GetValue(null)!;

            if (DeprecatedFrameworks.Contains(framework))
            {
                Assert.False(supportedFrameworks.Contains(framework), $"SupportedFrameworks should not contain the deprecated framework {field.Name}.");
            }
            else if (UnofficialFrameworks.Contains(framework))
            {
                Assert.False(supportedFrameworks.Contains(framework), $"SupportedFrameworks should not contain the unofficial framework {field.Name}.");
            }
            else
            {
                Assert.True(supportedFrameworks.Contains(framework), $"SupportedFrameworks is missing {field.Name} constant from CommonFrameworks.");
            }
        }
    }
}
