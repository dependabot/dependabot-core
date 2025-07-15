using System.Collections.Immutable;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class GlobalJsonBuildFile : JsonBuildFile
{
    public static GlobalJsonBuildFile Open(string basePath, string path, ILogger logger)
        => new(basePath, path, File.ReadAllText(path), logger);

    public GlobalJsonBuildFile(string basePath, string path, string contents, ILogger logger)
        : base(basePath, path, contents, logger)
    {
    }

    public JsonObject? MSBuildSdks => Node.Value is JsonObject root ? root["msbuild-sdks"]?.AsObject() : null;

    public IEnumerable<Dependency> GetDependencies()
    {
        if (MSBuildSdks is null)
        {
            return [];
        }

        var msBuildDependencies = MSBuildSdks
            .Select(t => GetSdkDependency(t.Key, t.Value))
            .ToImmutableArray();
        return msBuildDependencies;
    }

    private Dependency GetSdkDependency(string name, JsonNode? version)
    {
        return new Dependency(name, version?.GetValue<string>(), DependencyType.MSBuildSdk);
    }
}
