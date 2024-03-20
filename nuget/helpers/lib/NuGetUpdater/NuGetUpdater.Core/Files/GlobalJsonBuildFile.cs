using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class GlobalJsonBuildFile : JsonBuildFile
{
    public static GlobalJsonBuildFile Open(string repoRootPath, string path, Logger logger)
        => new(repoRootPath, path, File.ReadAllText(path), logger);

    public GlobalJsonBuildFile(string repoRootPath, string path, string contents, Logger logger)
        : base(repoRootPath, path, contents, logger)
    {
    }

    public JsonObject? Sdk
    {
        get
        {
            return Node.Value is JsonObject root ? root["sdk"]?.AsObject() : null;
        }
    }

    public JsonObject? MSBuildSdks
    {
        get
        {
            return Node.Value is JsonObject root ? root["msbuild-sdks"]?.AsObject() : null;
        }
    }

    public IEnumerable<Dependency> GetDependencies() => MSBuildSdks?.AsObject().Select(
        t => new Dependency(t.Key, t.Value?.GetValue<string>() ?? string.Empty, DependencyType.MSBuildSdk)) ?? Enumerable.Empty<Dependency>();
}
