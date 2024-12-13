using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using System.Text.Json.Serialization;

using Semver;

namespace DotNetPackageCorrelation;

public class SemVersionConverter : JsonConverter<SemVersion?>
{
    public override SemVersion? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (SemVersion.TryParse(value, out var result))
        {
            return result;
        }

        return null;
    }

    public override void Write(Utf8JsonWriter writer, SemVersion? value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value?.ToString());
    }

    public override void WriteAsPropertyName(Utf8JsonWriter writer, [DisallowNull] SemVersion value, JsonSerializerOptions options)
    {
        writer.WritePropertyName(value.ToString());
    }
}
