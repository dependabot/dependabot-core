using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class GlobalJsonBuildFile : JsonBuildFile
{
    public static GlobalJsonBuildFile Open(string repoRootPath, string path)
        => Parse(repoRootPath, path, File.ReadAllText(path));
    public static GlobalJsonBuildFile Parse(string repoRootPath, string path, string json)
        => new(repoRootPath, path, JsonNode.Parse(json)!);

    public GlobalJsonBuildFile(string repoRootPath, string path, JsonNode contents)
        : base(repoRootPath, path, contents)
    {
    }

    public JsonObject? Sdk => CurrentContents["sdk"]?.AsObject();

    public IEnumerable<KeyValuePair<string, JsonNode?>> MSBuildSdks =>
        CurrentContents["msbuild-sdks"]?.AsObject().ToArray() ?? Enumerable.Empty<KeyValuePair<string, JsonNode?>>();

    public IEnumerable<Dependency> GetDependencies() => MSBuildSdks.Select(
        t => new Dependency(t.Key, t.Value?.GetValue<string>() ?? string.Empty, DependencyType.MSBuildSdk));
}