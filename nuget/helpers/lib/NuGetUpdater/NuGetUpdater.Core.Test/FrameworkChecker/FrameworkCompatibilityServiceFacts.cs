// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Collections.Generic;
using System.Linq;

using NuGet.Frameworks;

using NuGetUpdater.Core.FrameworkChecker;

using Xunit;

namespace NuGetUpdater.Core.Test.FrameworkChecker;

public class FrameworkCompatibilityServiceFacts
{
    private readonly FrameworkCompatibilityService _service;
    private readonly IFrameworkCompatibilityProvider _compatibilityProvider = DefaultCompatibilityProvider.Instance;

    public FrameworkCompatibilityServiceFacts()
    {
        _service = new FrameworkCompatibilityService();
    }

    [Fact]
    public void NullPackageFrameworksThrowsArgumentNullException()
    {
        Assert.Throws<ArgumentNullException>(() => _service.GetCompatibleFrameworks(null));
    }

    [Fact]
    public void EmptyPackageFrameworksReturnsEmptySet()
    {
        var result = _service.GetCompatibleFrameworks(new List<NuGetFramework>());

        Assert.Empty(result);
    }

    [Fact]
    public void UnknownSupportedPackageReturnsSetWithSameFramework()
    {
        var framework = NuGetFramework.Parse("net45-client");
        var frameworks = new List<NuGetFramework> { framework };
        var compatible = _service.GetCompatibleFrameworks(frameworks);

        Assert.False(framework.IsUnsupported);
        Assert.Single(compatible);
        Assert.Contains(framework, compatible);
    }

    [Theory]
    [InlineData("1000")]
    [InlineData("lib")]
    [InlineData("nuget")]
    public void UnsupportedPackageFrameworksReturnsEmptySet(string unsupportedFrameworkName)
    {
        var unsupportedFramework = NuGetFramework.Parse(unsupportedFrameworkName);

        var result = _service.GetCompatibleFrameworks([unsupportedFramework]);

        Assert.True(unsupportedFramework.IsUnsupported);
        Assert.Empty(result);
    }

    [Theory]
    [InlineData("portable-net45+sl4+win8+wp7")]
    [InlineData("portable-net40+sl4")]
    [InlineData("portable-net45+sl5+win8+wpa81+wp8")]
    public void PCLPackageFrameworksReturnsEmptySet(string pclFrameworkName)
    {
        var portableFramework = NuGetFramework.Parse(pclFrameworkName);

        var result = _service.GetCompatibleFrameworks([portableFramework]);

        Assert.True(portableFramework.IsPCL);
        Assert.Empty(result);
    }

    [Theory]
    [InlineData("net5.0", "netcoreapp2.0", "win81")]
    [InlineData("sl4", "netstandard1.2", "netmf")]
    public void ValidPackageFrameworksReturnsFrameworksCompatibleForAtLeastOne(params string[] frameworkNames)
    {
        var frameworks = new List<NuGetFramework>();

        foreach (var frameworkName in frameworkNames)
        {
            frameworks.Add(NuGetFramework.Parse(frameworkName));
        }

        var compatibleFrameworks = _service.GetCompatibleFrameworks(frameworks);

        Assert.True(compatibleFrameworks.Count > 0);

        foreach (var compatibleFramework in compatibleFrameworks)
        {
            var isCompatible = frameworks.Any(f => _compatibilityProvider.IsCompatible(compatibleFramework, f));

            Assert.True(isCompatible);
        }
    }

    [Theory]
    [InlineData("net6.0-windows7.0", "net6.0-windows", "net6.0-windows7.0", "net7.0-windows", "net7.0-windows7.0")]
    public void WindowsPlatformVersionsShouldContainAllSpecifiedFrameworks(string windowsDefaultVersionFramework, params string[] windowsProjectFrameworks)
    {
        var packageFramework = NuGetFramework.Parse(windowsDefaultVersionFramework);
        var projectFrameworks = new HashSet<NuGetFramework>();

        foreach (var frameworkName in windowsProjectFrameworks)
        {
            projectFrameworks.Add(NuGetFramework.Parse(frameworkName));
        }

        var compatibleFrameworks = _service.GetCompatibleFrameworks([packageFramework]);
        Assert.Equal(windowsProjectFrameworks.Length, compatibleFrameworks.Count);

        var containsAllCompatibleFrameworks = compatibleFrameworks.All(cf => projectFrameworks.Contains(cf));
        Assert.True(containsAllCompatibleFrameworks);
    }
}
