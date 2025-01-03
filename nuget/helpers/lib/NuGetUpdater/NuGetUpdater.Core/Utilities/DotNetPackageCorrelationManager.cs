using System.Text.Json;

using DotNetPackageCorrelation;

using NuGetUpdater.Core.Discover;

namespace NuGetUpdater.Core.Utilities;

internal static class DotNetPackageCorrelationManager
{
    private static readonly PackageMapper _packageMapper;
    private static readonly Dictionary<string, PackageMapper> _packageMapperByOverrideFile = new();

    static DotNetPackageCorrelationManager()
    {
        var packageCorrelationPath = Path.Combine(Path.GetDirectoryName(typeof(SdkProjectDiscovery).Assembly.Location)!, "dotnet-package-correlation.json");
        var runtimePackages = LoadRuntimePackagesFromFile(packageCorrelationPath);
        _packageMapper = PackageMapper.Load(runtimePackages);
    }

    public static PackageMapper GetPackageMapper()
    {
        var packageCorrelationFileOverride = Environment.GetEnvironmentVariable("DOTNET_PACKAGE_CORRELATION_FILE_PATH");
        if (packageCorrelationFileOverride is not null)
        {
            // this is used as a test hook to allow unit tests to be SDK agnostic
            if (_packageMapperByOverrideFile.TryGetValue(packageCorrelationFileOverride, out var packageMapper))
            {
                return packageMapper;
            }

            var runtimePackages = LoadRuntimePackagesFromFile(packageCorrelationFileOverride);
            packageMapper = PackageMapper.Load(runtimePackages);
            _packageMapperByOverrideFile[packageCorrelationFileOverride] = packageMapper;
            return packageMapper;
        }

        return _packageMapper;
    }

    private static RuntimePackages LoadRuntimePackagesFromFile(string filePath)
    {
        var packageCorrelationJson = File.ReadAllText(filePath);
        return JsonSerializer.Deserialize<RuntimePackages>(packageCorrelationJson, Correlator.SerializerOptions)!;
    }
}
