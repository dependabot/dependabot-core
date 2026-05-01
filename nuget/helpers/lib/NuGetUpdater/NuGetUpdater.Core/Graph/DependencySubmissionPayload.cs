using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Graph;

public sealed record DependencySubmissionPayload
{
    public required int Version { get; init; }
    public required string Sha { get; init; }
    public required string Ref { get; init; }
    public required DependencySubmissionJob Job { get; init; }
    public required DependencySubmissionDetector Detector { get; init; }
    public required Dictionary<string, ManifestPayload> Manifests { get; init; }
    public required DependencySubmissionMetadata Metadata { get; init; }
}

public sealed record DependencySubmissionJob
{
    public required string Correlator { get; init; }
    public required string Id { get; init; }
}

public sealed record DependencySubmissionDetector
{
    public required string Name { get; init; }
    public required string Version { get; init; }
    public required string Url { get; init; }
}

public sealed record ManifestPayload
{
    public required string Name { get; init; }
    public required ManifestFile File { get; init; }
    public required ManifestMetadata Metadata { get; init; }
    public required Dictionary<string, ResolvedDependencyPayload> Resolved { get; init; }
}

public sealed record ManifestFile
{
    public required string SourceLocation { get; init; }
}

public sealed record ManifestMetadata
{
    public required string Ecosystem { get; init; }
}

public sealed record ResolvedDependencyPayload
{
    public required string PackageUrl { get; init; }
    public required string Relationship { get; init; }
    public required string Scope { get; init; }
    public required string[] Dependencies { get; init; }
}

public sealed record DependencySubmissionMetadata
{
    public required string Status { get; init; }

    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? Reason { get; init; }

    public required string ScannedManifestPath { get; init; }
}
