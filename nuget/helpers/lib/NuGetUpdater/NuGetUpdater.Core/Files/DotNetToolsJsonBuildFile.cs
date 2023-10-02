using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class DotNetToolsJsonBuildFile : JsonBuildFile
{
    public static DotNetToolsJsonBuildFile Open(string repoRootPath, string path)
        => Parse(repoRootPath, path, File.ReadAllText(path));
    public static DotNetToolsJsonBuildFile Parse(string repoRootPath, string path, string json)
        => new(repoRootPath, path, JsonNode.Parse(json)!);

    public DotNetToolsJsonBuildFile(string repoRootPath, string path, JsonNode contents)
        : base(repoRootPath, path, contents)
    {
    }

    public IEnumerable<KeyValuePair<string, JsonNode?>> Tools
        => CurrentContents["tools"]?.AsObject().ToArray() ?? Enumerable.Empty<KeyValuePair<string, JsonNode?>>();

    public IEnumerable<Dependency> GetDependencies() => Tools.Select(
        t => new Dependency(t.Key, t.Value?.AsObject()["version"]?.GetValue<string>() ?? string.Empty, DependencyType.DotNetTool));
}