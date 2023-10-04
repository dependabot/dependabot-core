using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal abstract class JsonBuildFile : BuildFile<JsonNode>
{
    public JsonBuildFile(string repoRootPath, string path, JsonNode contents)
        : base(repoRootPath, path, contents)
    {
    }

    protected override string GetContentsString(JsonNode contents)
        => contents.ToJsonString(new() { WriteIndented = true });
}