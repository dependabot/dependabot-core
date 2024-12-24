using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Analyze;

public class RequirementConverter : JsonConverter<Requirement>
{
    public override Requirement? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var text = reader.GetString();
        if (text is null)
        {
            throw new ArgumentNullException(nameof(text));
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
