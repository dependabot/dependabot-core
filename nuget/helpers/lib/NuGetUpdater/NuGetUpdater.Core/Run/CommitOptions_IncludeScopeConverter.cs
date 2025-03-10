using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run;

public class CommitOptions_IncludeScopeConverter : JsonConverter<bool>
{
    public override bool Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        switch (reader.TokenType)
        {
            case JsonTokenType.True:
                return true;
            case JsonTokenType.False:
            case JsonTokenType.Null:
                return false;
            case JsonTokenType.String:
                var stringValue = reader.GetString();
                return bool.Parse(stringValue!);
            default:
                throw new JsonException($"Unexpected token type {reader.TokenType}");
        }
    }

    public override void Write(Utf8JsonWriter writer, bool value, JsonSerializerOptions options)
    {
        writer.WriteBooleanValue(value);
    }
}
