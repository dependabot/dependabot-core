using System.Text.Json.Serialization;

namespace NuGetUpdater.Core.Run.ApiModel;

public sealed record MarkAsProcessed
{
    public MarkAsProcessed(string baseCommitSha)
    {
        BaseCommitSha = baseCommitSha;
    }

    [JsonPropertyName("base-commit-sha")]
    public string BaseCommitSha { get; }
}
