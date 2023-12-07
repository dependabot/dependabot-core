namespace NuGetUpdater.Core;

public enum DependencyType
{
    Unknown,
    PackageConfig,
    PackageReference,
    PackageVersion,
    GlobalPackageReference,
    DotNetTool,
    MSBuildSdk
}
