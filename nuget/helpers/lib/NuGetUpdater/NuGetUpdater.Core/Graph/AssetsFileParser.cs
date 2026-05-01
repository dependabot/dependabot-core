using System.Text.Json;

namespace NuGetUpdater.Core.Graph;

/// <summary>
/// Parses project.assets.json to extract dependency relationships.
/// The targets section maps each {PackageName}/{Version} to its direct dependencies.
/// </summary>
internal static class AssetsFileParser
{
    /// <summary>
    /// Parses project.assets.json and returns a mapping from package name to its direct dependency names.
    /// Only includes packages that are in the known dependency set.
    /// </summary>
    public static Dictionary<string, HashSet<string>> ParseDependencyRelationships(
        string assetsFilePath,
        HashSet<string> knownPackageNames,
        ILogger logger)
    {
        var relationships = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);

        try
        {
            if (!File.Exists(assetsFilePath))
            {
                return relationships;
            }

            var content = File.ReadAllText(assetsFilePath);
            var doc = JsonDocument.Parse(content);

            if (!doc.RootElement.TryGetProperty("targets", out var targets))
            {
                return relationships;
            }

            // Use the first TFM's targets (all TFMs typically have the same dependency relationships)
            foreach (var tfmEntry in targets.EnumerateObject())
            {
                foreach (var packageEntry in tfmEntry.Value.EnumerateObject())
                {
                    var parts = packageEntry.Name.Split('/');
                    if (parts.Length != 2)
                    {
                        continue;
                    }

                    var packageName = parts[0];
                    if (!knownPackageNames.Contains(packageName))
                    {
                        continue;
                    }

                    if (!packageEntry.Value.TryGetProperty("dependencies", out var deps))
                    {
                        continue;
                    }

                    var children = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                    foreach (var dep in deps.EnumerateObject())
                    {
                        if (knownPackageNames.Contains(dep.Name))
                        {
                            children.Add(dep.Name);
                        }
                    }

                    if (children.Count > 0)
                    {
                        // Merge with existing relationships (from multiple TFMs)
                        if (relationships.TryGetValue(packageName, out var existing))
                        {
                            existing.UnionWith(children);
                        }
                        else
                        {
                            relationships[packageName] = children;
                        }
                    }
                }

                // Use first TFM only to avoid duplicates
                break;
            }
        }
        catch (Exception ex)
        {
            logger.Warn($"Failed to parse dependency relationships from '{assetsFilePath}': {ex.Message}");
        }

        return relationships;
    }

    /// <summary>
    /// Finds the project.assets.json file for a given project file path.
    /// It's typically at {project_dir}/obj/project.assets.json.
    /// </summary>
    public static string? FindAssetsFile(string repoContentsPath, string workspacePath, string projectFilePath)
    {
        var projectDir = Path.GetDirectoryName(Path.Join(repoContentsPath, workspacePath, projectFilePath));
        if (projectDir is null)
        {
            return null;
        }

        var assetsPath = Path.Join(projectDir, "obj", "project.assets.json");
        return File.Exists(assetsPath) ? assetsPath : null;
    }
}
