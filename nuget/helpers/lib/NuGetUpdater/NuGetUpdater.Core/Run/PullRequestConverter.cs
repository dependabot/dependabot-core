using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

using NuGetUpdater.Core.Run.ApiModel;

namespace NuGetUpdater.Core.Analyze;

public class PullRequestConverter : JsonConverter<PullRequest>
{
    public override PullRequest? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        PullRequest? result;
        switch (reader.TokenType)
        {
            case JsonTokenType.StartArray:
                // old format, array of arrays of dependencies
                var dependencies = JsonSerializer.Deserialize<ImmutableArray<PullRequestDependency>>(ref reader, options);
                result = new PullRequest()
                {
                    Dependencies = dependencies
                };
                break;
            case JsonTokenType.StartObject:
                // new format, direct object
                // use the same deserializer options but exclude this special converter
                var optionsWithoutThisCustomConverter = new JsonSerializerOptions(options);
                for (int i = optionsWithoutThisCustomConverter.Converters.Count - 1; i >= 0; i--)
                {
                    if (optionsWithoutThisCustomConverter.Converters[i].GetType() == typeof(PullRequestConverter))
                    {
                        optionsWithoutThisCustomConverter.Converters.RemoveAt(i);
                    }
                }

                result = JsonSerializer.Deserialize<PullRequest>(ref reader, optionsWithoutThisCustomConverter);
                break;
            default:
                throw new JsonException("expected pull request object or array of pull request dependencies");
        }

        return result;
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
