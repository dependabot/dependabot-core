using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class GlobalJsonBuildFile : JsonBuildFile
{
    public static GlobalJsonBuildFile Open(string repoRootPath, string path)
        => Parse(repoRootPath, path, File.ReadAllText(path));
    public static GlobalJsonBuildFile Parse(string repoRootPath, string path, string json)
        => new(repoRootPath, path, JsonNode.Parse(json, new JsonNodeOptions { PropertyNameCaseInsensitive = true })!);

    public GlobalJsonBuildFile(string repoRootPath, string path, JsonNode contents)
        : base(repoRootPath, path, contents)
    {
    }

    public JsonObject? Sdk => Contents["sdk"]?.AsObject();

    public JsonObject? MSBuildSdks =>
        Contents["msbuild-sdks"]?.AsObject();

    public IEnumerable<Dependency> GetDependencies() => MSBuildSdks?.AsObject().Select(
        t => new Dependency(t.Key, t.Value?.GetValue<string>() ?? string.Empty, DependencyType.MSBuildSdk)) ?? Enumerable.Empty<Dependency>();
}