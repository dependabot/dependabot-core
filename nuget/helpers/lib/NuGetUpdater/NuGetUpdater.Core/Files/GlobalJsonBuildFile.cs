using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core;

internal sealed class GlobalJsonBuildFile : JsonBuildFile
{
    public static GlobalJsonBuildFile Open(string repoRootPath, string path)
        => new(repoRootPath, path, File.ReadAllText(path));

    public GlobalJsonBuildFile(string repoRootPath, string path, string contents)
        : base(repoRootPath, path, contents)
    {
    }

    public JsonObject? Sdk => Node.Value?["sdk"]?.AsObject();

    public JsonObject? MSBuildSdks =>
        Node.Value?["msbuild-sdks"]?.AsObject();

    public IEnumerable<Dependency> GetDependencies() => MSBuildSdks?.AsObject().Select(
        t => new Dependency(t.Key, t.Value?.GetValue<string>() ?? string.Empty, DependencyType.MSBuildSdk)) ?? Enumerable.Empty<Dependency>();
}
