using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class DotNetToolsJsonBuildFile : JsonBuildFile
{
    public static DotNetToolsJsonBuildFile Open(string basePath, string path, ILogger logger)
        => new(basePath, path, File.ReadAllText(path), logger);

    public DotNetToolsJsonBuildFile(string basePath, string path, string contents, ILogger logger)
        : base(basePath, path, contents, logger)
    {
    }

    public IEnumerable<KeyValuePair<string, JsonNode?>> Tools
        => Node.Value?["tools"]?.AsObject().ToArray() ?? Enumerable.Empty<KeyValuePair<string, JsonNode?>>();

    public IEnumerable<Dependency> GetDependencies() => Tools.Select(
        t => new Dependency(t.Key, t.Value?.AsObject()["version"]?.GetValue<string>() ?? string.Empty, DependencyType.DotNetTool));
}
