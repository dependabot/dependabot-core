using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Analyze;

public class RequirementConverter : JsonConverter<Requirement>
{
    public override Requirement? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        return Requirement.Parse(reader.GetString()!);
    }

    public override void Write(Utf8JsonWriter writer, Requirement value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToString());
    }
}
