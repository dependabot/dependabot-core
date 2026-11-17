using System.Text.Json;

using NuGet.Versioning;

using NuGetUpdater.Core.Analyze;

namespace NuGetUpdater.Core.Run;

public class PullRequestVersionConverter(ILogger logger) : VersionConverter
{
    public override NuGetVersion? Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var value = reader.GetString();
        if (NuGetVersion.TryParse(value, out var version))
        {
            return version;
        }

        logger.Warn($"Unable to parse existing pull request dependency version '{value}'; treating it as unknown.");
        return null;
    }
}
