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

    public IEnumerable<Dependency> GetDependencies()
    {
        List<Dependency> dependencies = [];
        if (Sdk is not null
            && Sdk.TryGetPropertyValue("version", out var version))
        {
            dependencies.Add(GetSdkDependency("Microsoft.NET.Sdk", version));
        }

        if (MSBuildSdks is null)
        {
            return dependencies;
        }

        var msBuildDependencies = MSBuildSdks
            .Select(t => GetSdkDependency(t.Key, t.Value));
        dependencies.AddRange(msBuildDependencies);
        return dependencies;
    }

    private Dependency GetSdkDependency(string name, JsonNode? version)
    {
        return new Dependency(name, version?.GetValue<string>(), DependencyType.MSBuildSdk);
    }
}
