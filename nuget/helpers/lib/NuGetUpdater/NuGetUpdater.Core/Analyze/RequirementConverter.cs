using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Analyze;

public class RequirementConverter : JsonConverter<Requirement>
{
    public override Requirement? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType != JsonTokenType.String)
        {
            throw new BadRequirementException($"Expected token type {nameof(JsonTokenType.String)}, but found {reader.TokenType}.");
        }

        var text = reader.GetString();
        if (text is null)
        {
            throw new BadRequirementException("Unexpected null token.");
        }

        try
        {
            return Requirement.Parse(text);
        }
        catch
        {
            throw new BadRequirementException(text);
        }
    }

    public override void Write(Utf8JsonWriter writer, Requirement value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToString());
    }
}
