namespace NuGetUpdater.Core;

public enum DependencyType
{
    Unknown,
    PackagesConfig,
    PackageReference,
    PackageVersion,
    GlobalPackageReference,
    DotNetTool,
    MSBuildSdk
}
