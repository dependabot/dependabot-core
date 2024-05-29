using System.Collections.Immutable;

using NuGet.CommandLine;
using NuGet.Common;
using NuGet.Configuration;
using NuGet.Protocol.Core.Types;

namespace NuGetUpdater.Analyzer;

internal record NuGetContext : IDisposable
{
    public SourceCacheContext SourceCacheContext { get; }
    public string CurrentDirectory { get; }
    public ISettings Settings { get; }
    public IMachineWideSettings MachineWideSettings { get; }
    public ImmutableArray<PackageSource> PackageSources { get; }
    public ILogger Logger { get; }
    public string TempPackageDirectory { get; }

    public NuGetContext(string? currentDirectory = null, ILogger? logger = null)
    {
        SourceCacheContext = new SourceCacheContext();
        CurrentDirectory = currentDirectory ?? Environment.CurrentDirectory;
        MachineWideSettings = new CommandLineMachineWideSettings();
        Settings = NuGet.Configuration.Settings.LoadDefaultSettings(
            CurrentDirectory,
            configFileName: null,
            MachineWideSettings);
        var sourceProvider = new PackageSourceProvider(Settings);
        PackageSources = sourceProvider.LoadPackageSources()
            .Where(p => p.IsEnabled)
            .ToImmutableArray();
        Logger = logger ?? NullLogger.Instance;
        TempPackageDirectory = Path.Combine(Path.GetTempPath(), ".dependabot", "packages");
    }

    public void Dispose()
    {
        SourceCacheContext?.Dispose();
    }
}
