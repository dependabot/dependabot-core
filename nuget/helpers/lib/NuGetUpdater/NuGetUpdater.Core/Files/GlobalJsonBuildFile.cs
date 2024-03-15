using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class GlobalJsonBuildFile : JsonBuildFile
{
    public static GlobalJsonBuildFile Open(string basePath, string path, Logger logger)
        => new(basePath, path, File.ReadAllText(path), logger);

    public GlobalJsonBuildFile(string basePath, string path, string contents, Logger logger)
        : base(basePath, path, contents, logger)
    {
    }

    public JsonObject? Sdk => Node.Value is JsonObject root ? root["sdk"]?.AsObject() : null;

    public JsonObject? MSBuildSdks => Node.Value is JsonObject root ? root["msbuild-sdks"]?.AsObject() : null;

    public IEnumerable<Dependency> GetDependencies() => MSBuildSdks?.AsObject().Select(
        t => new Dependency(t.Key, t.Value?.GetValue<string>() ?? string.Empty, DependencyType.MSBuildSdk)) ?? Enumerable.Empty<Dependency>();
}
