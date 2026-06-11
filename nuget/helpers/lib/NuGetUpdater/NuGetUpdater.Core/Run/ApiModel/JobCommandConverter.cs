using System.Text.Json;
using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public class JobCommandConverter : JsonConverter<JobCommand>
{
    private readonly ILogger _logger;

    public JobCommandConverter(ILogger logger)
    {
        _logger = logger;
    }

    public override JobCommand Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        if (reader.TokenType == JsonTokenType.Null)
        {
            return JobCommand.None;
        }

        var value = reader.GetString();
        return value switch
        {
            "" => JobCommand.None,
            "update" => JobCommand.Update,
            "recreate" => JobCommand.Recreate,
            "graph" => JobCommand.Graph,
            _ => LogAndDefault(value),
        };
    }

    private JobCommand LogAndDefault(string? value)
    {
        _logger.Warn($"Unknown job command value: \"{value}\"; defaulting to None.");
        return JobCommand.None;
    }

    public override void Write(Utf8JsonWriter writer, JobCommand value, JsonSerializerOptions options)
    {
        var str = value switch
        {
            JobCommand.Update => "update",
            JobCommand.Recreate => "recreate",
            JobCommand.Graph => "graph",
            _ => "",
        };
        writer.WriteStringValue(str);
    }
}
