using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class DotNetToolsJsonBuildFile : JsonBuildFile
{
    public static DotNetToolsJsonBuildFile Open(string repoRootPath, string path)
        => new(repoRootPath, path, File.ReadAllText(path));

    public DotNetToolsJsonBuildFile(string repoRootPath, string path, string contents)
        : base(repoRootPath, path, contents)
    {
    }

    public IEnumerable<KeyValuePair<string, JsonNode?>> Tools
        => Node.Value?["tools"]?.AsObject().ToArray() ?? Enumerable.Empty<KeyValuePair<string, JsonNode?>>();

    public IEnumerable<Dependency> GetDependencies() => Tools.Select(
        t => new Dependency(t.Key, t.Value?.AsObject()["version"]?.GetValue<string>() ?? string.Empty, DependencyType.DotNetTool));
}
