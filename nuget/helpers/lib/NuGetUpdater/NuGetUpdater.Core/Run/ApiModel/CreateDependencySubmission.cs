using System.Text;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record CreateDependencySubmission : MessageBase
{
    public required int Version { get; init; }

    public required string Sha { get; init; }

    public required string Ref { get; init; }

    public required SubmissionJob Job { get; init; }

    public required SubmissionDetector Detector { get; init; }

    public required Dictionary<string, Manifest> Manifests { get; init; }

    public required SubmissionMetadata Metadata { get; init; }

    public override string GetReport()
    {
        var report = new StringBuilder();
        report.AppendLine(nameof(CreateDependencySubmission));
        report.AppendLine($"- Status: {Metadata.Status}");
        report.AppendLine($"- Scanned: {Metadata.ScannedManifestPath}");
        report.AppendLine($"- Manifests: {Manifests.Count}");
        return report.ToString().Trim();
    }

    public sealed record SubmissionJob
    {
        public required string Correlator { get; init; }

        public required string Id { get; init; }
    }

    public sealed record SubmissionDetector
    {
        public required string Name { get; init; }

        public required string Version { get; init; }

        public required string Url { get; init; }
    }

    public sealed record Manifest
    {
        public required string Name { get; init; }

        public required ManifestFile File { get; init; }

        public required ManifestMetadata Metadata { get; init; }

        public required Dictionary<string, ResolvedDependency> Resolved { get; init; }
    }

    public sealed record ManifestFile
    {
        [JsonPropertyName("source_location")]
        public required string SourceLocation { get; init; }
    }

    public sealed record ManifestMetadata
    {
        public required string Ecosystem { get; init; }
    }

    public sealed record ResolvedDependency
    {
        [JsonPropertyName("package_url")]
        public required string PackageUrl { get; init; }

        public required string Relationship { get; init; }

        public required string Scope { get; init; }

        public required string[] Dependencies { get; init; }
    }

    public sealed record SubmissionMetadata
    {
        public required string Status { get; init; }

        [JsonPropertyName("scanned_manifest_path")]
        public required string ScannedManifestPath { get; init; }

        [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
        public string? Reason { get; init; }
    }
}
