using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record DependencyFile
{
    public required string Name { get; init; }
    public required string Content { get; init; }
    public required string Directory { get; init; }
    public string Type { get; init; } = "file"; // TODO: enum
    [JsonPropertyName("support_file")]
    public bool SupportFile { get; init; } = false;
    [JsonPropertyName("content_encoding")]
    public string ContentEncoding { get; init; } = "utf-8";
    public bool Deleted { get; init; } = false;
    public string Operation { get; init; } = "update"; // TODO: enum
    public string? Mode { get; init; } = null; // TODO: what is this?
}
