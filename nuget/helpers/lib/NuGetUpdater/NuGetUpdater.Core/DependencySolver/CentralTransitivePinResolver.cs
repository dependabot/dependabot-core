using System.Collections.Immutable;
using System.Text.Json;
using System.Xml.Linq;

using NuGet.Versioning;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.DependencySolver;

internal static class CentralTransitivePinResolver
{
    private sealed record ResolvedPackage(NuGetVersion Version, Dictionary<string, VersionRange> Dependencies);

    public static async Task<ImmutableArray<Dependency>?> ResolveAsync(
        string tempProjectPath,
        ImmutableArray<Dependency> originalDependencies,
        ImmutableArray<Dependency> candidateDependencies,
        ILogger logger)
    {
        var pins = originalDependencies
            .Where(d => !d.IsTopLevel)
            .ToDictionary(d => d.Name, StringComparer.OrdinalIgnoreCase);
        if (pins.Count == 0)
        {
            return candidateDependencies;
        }

        var candidates = candidateDependencies.ToDictionary(d => d.Name, StringComparer.OrdinalIgnoreCase);
        var originalByName = originalDependencies.ToDictionary(d => d.Name, StringComparer.OrdinalIgnoreCase);
        var pinMinimums = new Dictionary<string, NuGetVersion>(StringComparer.OrdinalIgnoreCase);
        foreach (var pin in pins.Values)
        {
            if (!candidates.TryGetValue(pin.Name, out var candidate) ||
                !NuGetVersion.TryParse(candidate.Version, out var version))
            {
                return null;
            }

            pinMinimums[pin.Name] = version;
        }

        var projectDirectory = Path.GetDirectoryName(tempProjectPath)!;
        var assetsPath = Path.Join(projectDirectory, "obj", "project.assets.json");
        var project = XDocument.Load(tempProjectPath);
        var packageGroup = project.Root?.Element("ItemGroup");
        if (packageGroup is null)
        {
            return null;
        }

        var pinRanges = new Dictionary<string, VersionRange>(StringComparer.OrdinalIgnoreCase);
        var seenStates = new HashSet<string>(StringComparer.Ordinal);
        // Restore exact candidates first, then relax only insufficient pins to their parents' combined range.
        while (true)
        {
            var state = string.Join("|", pinRanges.OrderBy(p => p.Key, StringComparer.OrdinalIgnoreCase).Select(p => $"{p.Key}/{p.Value}"));
            if (!seenStates.Add(state))
            {
                logger.Warn("Unable to resolve central transitive pins without cycling between versions.");
                return null;
            }

            packageGroup.RemoveNodes();
            foreach (var candidate in candidateDependencies)
            {
                if (string.IsNullOrWhiteSpace(candidate.Version))
                {
                    return null;
                }

                var nameAttribute = originalByName.TryGetValue(candidate.Name, out var original) && original.IsUpdate
                    ? "Update"
                    : "Include";
                var version = pinRanges.TryGetValue(candidate.Name, out var range)
                    ? range.ToString()
                    : MSBuildHelper.GetExactVersionConstraint(candidate.Version);
                packageGroup.Add(new XElement("PackageReference", new XAttribute(nameAttribute, candidate.Name), new XAttribute("Version", version)));
            }

            await File.WriteAllTextAsync(tempProjectPath, project.ToString());
            File.Delete(assetsPath);
            var (exitCode, _, _) = await ProcessEx.RunDotnetWithoutMSBuildEnvironmentVariablesAsync(["restore", tempProjectPath], projectDirectory);
            if (!File.Exists(assetsPath))
            {
                logger.Warn("Unable to read the dependency graph for central transitive pins.");
                return null;
            }

            using var assets = JsonDocument.Parse(await File.ReadAllTextAsync(assetsPath));
            if (!TryReadGraph(assets.RootElement, out var graph))
            {
                logger.Warn("Unable to read the dependency graph for central transitive pins.");
                return null;
            }

            var reachable = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var pending = new Queue<string>(candidateDependencies
                .Where(d => !pins.ContainsKey(d.Name) && (!originalByName.TryGetValue(d.Name, out var original) || !original.IsUpdate))
                .Select(d => d.Name));
            var constraints = new Dictionary<string, List<VersionRange>>(StringComparer.OrdinalIgnoreCase);
            while (pending.TryDequeue(out var name))
            {
                if (!reachable.Add(name) || !graph.TryGetValue(name, out var package))
                {
                    continue;
                }

                foreach (var (dependencyName, dependencyRange) in package.Dependencies)
                {
                    if (pins.ContainsKey(dependencyName))
                    {
                        if (!constraints.TryGetValue(dependencyName, out var ranges))
                        {
                            ranges = [];
                            constraints[dependencyName] = ranges;
                        }

                        ranges.Add(dependencyRange);
                    }

                    pending.Enqueue(dependencyName);
                }
            }

            var errors = assets.RootElement.TryGetProperty("logs", out var logs)
                ? logs.EnumerateArray()
                    .Where(log => log.TryGetProperty("level", out var level) && level.GetString() == "Error")
                    .ToArray()
                : [];
            if (exitCode != 0 && errors.Length == 0)
            {
                return null;
            }

            var hasPinDowngrade = false;
            foreach (var error in errors)
            {
                var code = error.TryGetProperty("code", out var codeValue) ? codeValue.GetString() : null;
                var packageName = error.TryGetProperty("libraryId", out var libraryId) ? libraryId.GetString() : null;
                if (packageName is not null && code == "NU1605" && pins.ContainsKey(packageName) && constraints.ContainsKey(packageName))
                {
                    hasPinDowngrade = true;
                    continue;
                }

                if (packageName is not null && code == "NU1202" &&
                    originalByName.TryGetValue(packageName, out var original) &&
                    candidates.TryGetValue(packageName, out var candidate) &&
                    NuGetVersion.TryParse(original.Version, out var originalVersion) &&
                    graph.TryGetValue(packageName, out var resolvedPackage) &&
                    resolvedPackage.Version == originalVersion &&
                    NuGetVersion.TryParse(candidate.Version, out var candidateVersion) &&
                    candidateVersion == originalVersion)
                {
                    // Preserve the existing exemption for unchanged, incompatible packages.
                    continue;
                }

                logger.Warn($"Unable to resolve central transitive pins: {code ?? "unknown restore error"}.");
                return null;
            }

            var changed = false;
            foreach (var (pinName, minimumVersion) in pinMinimums)
            {
                if (!reachable.Contains(pinName) || !constraints.TryGetValue(pinName, out var ranges))
                {
                    changed |= pinRanges.Remove(pinName);
                    continue;
                }

                if (!graph.TryGetValue(pinName, out var resolvedPin))
                {
                    return null;
                }

                var needsHigherVersion = ranges.Any(range =>
                    range.MinVersion is { } minimum &&
                    (resolvedPin.Version < minimum || (resolvedPin.Version == minimum && !range.IsMinInclusive)));
                if (!needsHigherVersion && !pinRanges.ContainsKey(pinName))
                {
                    continue;
                }

                var combinedRange = VersionRange.CommonSubSet(ranges.Prepend(new VersionRange(minimumVersion)));
                if (combinedRange.Equals(VersionRange.None))
                {
                    logger.Warn($"No compatible version range exists for central transitive pin {pinName}.");
                    return null;
                }

                if (!pinRanges.TryGetValue(pinName, out var previousRange) || previousRange.ToString() != combinedRange.ToString())
                {
                    pinRanges[pinName] = combinedRange;
                    changed = true;
                }
                else if (ranges.Any(range => !range.Satisfies(resolvedPin.Version)))
                {
                    return null;
                }
            }

            if (changed)
            {
                continue;
            }

            if (hasPinDowngrade)
            {
                return null;
            }

            return [.. candidateDependencies.Select(dependency =>
                pinRanges.ContainsKey(dependency.Name) && graph.TryGetValue(dependency.Name, out var resolved)
                    ? dependency with { Version = resolved.Version.ToNormalizedString() }
                    : dependency)];
        }
    }

    private static bool TryReadGraph(JsonElement assets, out Dictionary<string, ResolvedPackage> graph)
    {
        graph = new(StringComparer.OrdinalIgnoreCase);
        if (!assets.TryGetProperty("targets", out var targets))
        {
            return false;
        }

        foreach (var target in targets.EnumerateObject())
        {
            foreach (var package in target.Value.EnumerateObject())
            {
                var separator = package.Name.LastIndexOf('/');
                if (separator <= 0 || !NuGetVersion.TryParse(package.Name[(separator + 1)..], out var version))
                {
                    continue;
                }

                var dependencies = new Dictionary<string, VersionRange>(StringComparer.OrdinalIgnoreCase);
                if (package.Value.TryGetProperty("dependencies", out var dependencyElements))
                {
                    foreach (var dependency in dependencyElements.EnumerateObject())
                    {
                        var versionString = dependency.Value.ValueKind == JsonValueKind.String ? dependency.Value.GetString() : null;
                        if (versionString is null || !VersionRange.TryParse(versionString, out var range))
                        {
                            return false;
                        }

                        dependencies[dependency.Name] = range;
                    }
                }

                graph[package.Name[..separator]] = new ResolvedPackage(version, dependencies);
            }
        }

        return true;
    }
}
