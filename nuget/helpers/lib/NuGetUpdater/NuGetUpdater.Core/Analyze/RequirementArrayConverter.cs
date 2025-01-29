using System.Collections.Immutable;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Analyze;

public class RequirementArrayConverter : JsonConverter<ImmutableArray<Requirement>>
{
    public override ImmutableArray<Requirement> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var requirements = new List<Requirement>();
        var requirementStrings = JsonSerializer.Deserialize<string[]>(ref reader, options) ?? [];
        foreach (var requirementString in requirementStrings)
        {
            try
            {
                var requirement = Requirement.Parse(requirementString);
                requirements.Add(requirement);
            }
            catch (ArgumentException)
            {
                // couldn't parse, nothing to do
            }
        }

        return requirements.ToImmutableArray();
    }

    public override void Write(Utf8JsonWriter writer, ImmutableArray<Requirement> value, JsonSerializerOptions options)
    {
        writer.WriteStartArray();
        foreach (var requirement in value)
        {
            writer.WriteStringValue(requirement.ToString());
        }

        writer.WriteEndArray();
    }
}
