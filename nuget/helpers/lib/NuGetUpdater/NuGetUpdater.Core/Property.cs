namespace NuGetUpdater.Core;

public sealed record Property(
    string Name,
    string Value,
    string SourceFilePath);
