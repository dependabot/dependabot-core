using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Discover;

/// <summary>
/// Serializes a dependency graph with its keys and values in alphabetical order so the output is stable.
/// </summary>
public class DependencyGraphConverter : JsonConverter<ImmutableDictionary<string, ImmutableArray<string>>>
{
    public override ImmutableDictionary<string, ImmutableArray<string>> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var graph = JsonSerializer.Deserialize<Dictionary<string, ImmutableArray<string>>>(ref reader, options);
        return graph?.ToImmutableDictionary(StringComparer.OrdinalIgnoreCase) ?? ImmutableDictionary<string, ImmutableArray<string>>.Empty;
    }

    public override void Write(Utf8JsonWriter writer, ImmutableDictionary<string, ImmutableArray<string>> value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        foreach (var (key, dependencies) in value.OrderBy(kvp => kvp.Key, StringComparer.OrdinalIgnoreCase).ThenBy(kvp => kvp.Key, StringComparer.Ordinal))
        {
            writer.WritePropertyName(key);
            writer.WriteStartArray();
            foreach (var dependency in dependencies.OrderBy(d => d, StringComparer.OrdinalIgnoreCase).ThenBy(d => d, StringComparer.Ordinal))
            {
                writer.WriteStringValue(dependency);
            }

            writer.WriteEndArray();
        }

        writer.WriteEndObject();
    }
}
