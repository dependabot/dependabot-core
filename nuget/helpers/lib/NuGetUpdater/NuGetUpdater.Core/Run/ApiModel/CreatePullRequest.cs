using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record CreatePullRequest : MessageBase
{
    public required ReportedDependency[] Dependencies { get; init; }

    [JsonPropertyName("updated-dependency-files")]
    public required DependencyFile[] UpdatedDependencyFiles { get; init; }

    [JsonPropertyName("base-commit-sha")]
    public required string BaseCommitSha { get; init; }

    [JsonPropertyName("commit-message")]
    public required string CommitMessage { get; init; }

    [JsonPropertyName("pr-title")]
    public required string PrTitle { get; init; }

    [JsonPropertyName("pr-body")]
    public required string PrBody { get; init; }

    /// <summary>
    /// This is serialized as either `null` or `{"name": "group-name"}`.
    /// </summary>
    [JsonPropertyName("dependency-group")]
    [JsonConverter(typeof(DependencyGroupConverter))]
    public required string? DependencyGroup { get; init; }

    public override string GetReport()
    {
        var dependencyNames = Dependencies
            .OrderBy(d => d.Name, StringComparer.OrdinalIgnoreCase)
            .ThenBy(d => NuGetVersion.Parse(d.Version!))
            .Select(d => $"{d.Name}/{d.Version}")
            .ToArray();
        var report = new StringBuilder();
        report.AppendLine(nameof(CreatePullRequest));
        foreach (var d in dependencyNames)
        {
            report.AppendLine($"- {d}");
        }

        return report.ToString().Trim();
    }

    public class DependencyGroupConverter : JsonConverter<string?>
    {
        public override string? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            if (reader.TokenType == JsonTokenType.Null)
            {
                return null;
            }

            var dict = JsonSerializer.Deserialize<Dictionary<string, string>>(ref reader, options);
            if (dict is not null &&
                dict.TryGetValue("name", out var name))
            {
                return name;
            }

            throw new NotSupportedException("Expected an object with a `name` property.");
        }

        public override void Write(Utf8JsonWriter writer, string? value, JsonSerializerOptions options)
        {
            if (value is null)
            {
                writer.WriteNullValue();
            }
            else
            {
                writer.WriteStartObject();
                writer.WriteString("name", value);
                writer.WriteEndObject();
            }
        }
    }
}
