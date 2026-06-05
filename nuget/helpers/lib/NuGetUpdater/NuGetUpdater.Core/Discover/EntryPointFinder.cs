using System.Collections.Immutable;

using Microsoft.Build.Construction;
using Microsoft.Build.Definition;
using Microsoft.Build.Evaluation;

using Microsoft.VisualStudio.SolutionPersistence.Serializer;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Discover;

internal static class EntryPointFinder
{
    private static readonly string[] EntryPointExtensions = [".sln", ".slnx", ".proj"];
    private static readonly string[] ProjectExtensions = [".csproj", ".vbproj", ".fsproj"];

    /// <summary>
    /// Given a set of job directories and a repo root, finds the minimal set of directories
    /// that contain the ultimate parent entry point files (e.g., .sln, .proj) for all projects
    /// found in the original directories.
    /// </summary>
    internal static async Task<ImmutableArray<string>> FindRootDirectoriesAsync(ImmutableArray<string> jobDirectories, string repoRootPath, ILogger logger)
    {
        var entryPointFiles = ScanForEntryPointFiles(repoRootPath);
        if (entryPointFiles.Length == 0)
        {
            logger.Info("  No entry point files found; keeping original directories.");
            return jobDirectories;
        }

        var childToParentMap = await BuildChildToParentMapAsync(entryPointFiles, logger);
        if (childToParentMap.Count == 0)
        {
            logger.Info("  No parent relationships found; keeping original directories.");
            return jobDirectories;
        }

        var rootDirectories = new HashSet<string>(PathComparer.Instance);

        foreach (var directory in jobDirectories)
        {
            var fullDirectoryPath = PathHelper.GetFullPathFromRelative(repoRootPath, directory);
            var projectFiles = FindProjectFilesInDirectory(fullDirectoryPath);

            if (projectFiles.Length == 0)
            {
                // no project files in this directory; check if any entry point files exist here
                var entryPointsHere = FindEntryPointFilesInDirectory(fullDirectoryPath);
                if (entryPointsHere.Length == 0)
                {
                    rootDirectories.Add(directory);
                    continue;
                }

                // walk these entry points up to their roots
                foreach (var entryPoint in entryPointsHere)
                {
                    var roots = WalkToRoots(entryPoint, childToParentMap);
                    foreach (var root in roots)
                    {
                        var rootDir = PathHelper.GetRelativeDirectoryOf(root, repoRootPath);
                        rootDirectories.Add(rootDir);
                    }
                }
            }
            else
            {
                foreach (var projectFile in projectFiles)
                {
                    var roots = WalkToRoots(projectFile, childToParentMap);
                    if (roots.Count == 0)
                    {
                        // no parent found; keep original directory
                        rootDirectories.Add(directory);
                    }
                    else
                    {
                        foreach (var root in roots)
                        {
                            var rootDir = PathHelper.GetRelativeDirectoryOf(root, repoRootPath);
                            rootDirectories.Add(rootDir);
                        }
                    }
                }
            }
        }

        var result = rootDirectories.OrderBy(d => d, StringComparer.OrdinalIgnoreCase).ToImmutableArray();
        logger.Info($"  Resolved root directories: [{string.Join(", ", result)}]");
        return result;
    }

    internal static ImmutableArray<string> ScanForEntryPointFiles(string repoRootPath)
    {
        var result = new List<string>();
        foreach (var extension in EntryPointExtensions)
        {
            var files = Directory.EnumerateFiles(repoRootPath, $"*{extension}", SearchOption.AllDirectories);
            result.AddRange(files.Select(f => Path.GetFullPath(f)));
        }

        return [.. result];
    }

    internal static async Task<Dictionary<string, HashSet<string>>> BuildChildToParentMapAsync(ImmutableArray<string> entryPointFiles, ILogger logger)
    {
        var childToParent = new Dictionary<string, HashSet<string>>(PathComparer.Instance);

        foreach (var parentFile in entryPointFiles)
        {
            var children = await GetChildrenOfEntryPointAsync(parentFile, logger);
            foreach (var child in children)
            {
                if (!childToParent.TryGetValue(child, out var parents))
                {
                    parents = new HashSet<string>(PathComparer.Instance);
                    childToParent[child] = parents;
                }

                parents.Add(parentFile);
            }
        }

        return childToParent;
    }

    internal static async Task<ImmutableArray<string>> GetChildrenOfEntryPointAsync(string entryPointPath, ILogger logger)
    {
        var extension = Path.GetExtension(entryPointPath).ToLowerInvariant();
        try
        {
            return extension switch
            {
                ".sln" => GetChildrenOfSolution(entryPointPath),
                ".slnx" => await GetChildrenOfSlnxAsync(entryPointPath),
                ".proj" => GetChildrenOfProj(entryPointPath),
                _ => [],
            };
        }
        catch (Exception ex)
        {
            logger.Info($"  Warning: failed to parse {entryPointPath}: {ex.Message}");
            return [];
        }
    }

    private static ImmutableArray<string> GetChildrenOfSolution(string solutionPath)
    {
        var solution = SolutionFile.Parse(solutionPath);
        return solution.ProjectsInOrder
            .Select(p => Path.GetFullPath(p.AbsolutePath))
            .ToImmutableArray();
    }

    private static async Task<ImmutableArray<string>> GetChildrenOfSlnxAsync(string slnxPath)
    {
        var solution = await SolutionSerializers.SlnXml.OpenAsync(slnxPath, CancellationToken.None);
        var solutionDir = Path.GetDirectoryName(slnxPath) ?? string.Empty;
        return solution.SolutionProjects
            .Select(p => PathHelper.GetFullPathFromRelative(solutionDir, p.FilePath))
            .ToImmutableArray();
    }

    /// <summary>
    /// Parses a .proj file using MSBuild evaluation to extract referenced projects.
    /// MSBuild must be registered via <see cref="MSBuildHelper.RegisterMSBuild"/> before calling this method.
    /// </summary>
    private static ImmutableArray<string> GetChildrenOfProj(string projPath)
    {
        if (!File.Exists(projPath))
        {
            return [];
        }

        using var projectCollection = new ProjectCollection();
        var project = Project.FromFile(projPath, new ProjectOptions
        {
            LoadSettings = ProjectLoadSettings.IgnoreMissingImports | ProjectLoadSettings.IgnoreEmptyImports | ProjectLoadSettings.IgnoreInvalidImports,
            ProjectCollection = projectCollection,
        });

        var itemTypes = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "ProjectFile", "ProjectReference" };
        var projectItems = project.Items.Where(i => itemTypes.Contains(i.ItemType)).ToList();
        var projectDir = Path.GetDirectoryName(projPath)!;
        var result = new HashSet<string>(PathComparer.Instance);

        foreach (var item in projectItems)
        {
            var evaluatedInclude = item.EvaluatedInclude;
            var normalizedPath = Path.IsPathRooted(evaluatedInclude)
                ? Path.GetFullPath(evaluatedInclude)
                : PathHelper.GetFullPathFromRelative(projectDir, evaluatedInclude);
            result.Add(normalizedPath);
        }

        return [.. result];
    }

    /// <summary>
    /// Walks from a file upward through the child-to-parent map until reaching files with no parents.
    /// Returns the set of root files found.
    /// </summary>
    internal static HashSet<string> WalkToRoots(string startFile, Dictionary<string, HashSet<string>> childToParentMap)
    {
        var roots = new HashSet<string>(PathComparer.Instance);
        var visited = new HashSet<string>(PathComparer.Instance);
        var queue = new Queue<string>();
        queue.Enqueue(startFile);

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();
            if (!visited.Add(current))
            {
                continue;
            }

            if (childToParentMap.TryGetValue(current, out var parents) && parents.Count > 0)
            {
                foreach (var parent in parents)
                {
                    queue.Enqueue(parent);
                }
            }
            else
            {
                roots.Add(current);
            }
        }

        return roots;
    }

    private static ImmutableArray<string> FindProjectFilesInDirectory(string directoryPath)
        => FindFilesInDirectory(directoryPath, ProjectExtensions);

    private static ImmutableArray<string> FindEntryPointFilesInDirectory(string directoryPath)
        => FindFilesInDirectory(directoryPath, EntryPointExtensions);

    private static ImmutableArray<string> FindFilesInDirectory(string directoryPath, string[] extensions)
    {
        if (!Directory.Exists(directoryPath))
        {
            return [];
        }

        var result = new List<string>();
        foreach (var extension in extensions)
        {
            result.AddRange(
                Directory.EnumerateFiles(directoryPath, $"*{extension}", SearchOption.TopDirectoryOnly)
                    .Select(Path.GetFullPath));
        }

        return [.. result];
    }
}
