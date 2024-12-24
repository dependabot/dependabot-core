using System.Text.Json;
using System.Text.Json.Serialization;

using NuGet.Versioning;

namespace NuGetUpdater.Core.Analyze;

public class VersionConverter : JsonConverter<NuGetVersion>
{
    public override NuGetVersion? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        return NuGetVersion.Parse(reader.GetString()!);
    }

    public override void Write(Utf8JsonWriter writer, NuGetVersion value, JsonSerializerOptions options)
    {
        writer.WriteStringValue(value.ToString());
    }
}
