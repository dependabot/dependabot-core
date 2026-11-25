using System.Collections.Immutable;

namespace NuGetUpdater.Core.Discover;

public record TargetFrameworkFallback(ImmutableArray<string> Imports, bool AssetTargetFallback);
