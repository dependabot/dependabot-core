namespace NuGetUpdater.Core;

public sealed record Dependency(string Name, string? Version, DependencyType Type, bool IsDevDependency = false, bool IsOverride = false, bool IsUpdate = false);
