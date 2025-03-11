using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Analyze;

public class PullRequestConverter : JsonConverter<PullRequest>
{
    public override PullRequest? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.StartArray)
        {
            throw new JsonException("expected array of pull request dependencies");
        }

        var dependencies = JsonSerializer.Deserialize<ImmutableArray<PullRequestDependency>>(ref reader, options);
        return new PullRequest()
        {
            Dependencies = dependencies
        };
    }

    public override void Write(Utf8JsonWriter writer, PullRequest value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        foreach (var dependency in value.Dependencies)
        {
            JsonSerializer.Serialize(writer, dependency, options);
        }

        writer.WriteEndArray();
    }
}
