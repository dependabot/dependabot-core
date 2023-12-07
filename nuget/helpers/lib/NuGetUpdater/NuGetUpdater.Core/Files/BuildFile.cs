using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

using DiffPlex;
using DiffPlex.DiffBuilder;
using DiffPlex.DiffBuilder.Model;

namespace NuGetUpdater.Core;

internal abstract class BuildFile
{
    public string RepoRootPath { get; }
    public string Path { get; }
    public string RepoRelativePath => System.IO.Path.GetRelativePath(RepoRootPath, Path);

    public BuildFile(string repoRootPath, string path)
    {
        RepoRootPath = repoRootPath;
        Path = path;
    }

    public abstract Task<bool> SaveAsync();

    public static IEnumerable<Dependency> GetDependencies(BuildFile buildFile)
    {
        return buildFile switch
        {
            ProjectBuildFile projectBuildFile => projectBuildFile.GetDependencies(),
            PackagesConfigBuildFile packagesConfigBuildFile => packagesConfigBuildFile.GetDependencies(),
            GlobalJsonBuildFile globalJsonBuildFile => globalJsonBuildFile.GetDependencies(),
            DotNetToolsJsonBuildFile dotnetToolsJsonBuildFile => dotnetToolsJsonBuildFile.GetDependencies(),
            _ => throw new NotSupportedException($"Build files of type [{buildFile.GetType().Name}] are not supported.")
        };
    }
}

internal abstract partial class BuildFile<T>
    : BuildFile where T : class
{
    public T Contents { get; private set; }

    private string _originalContentsText;

    public BuildFile(string repoRootPath, string path, T contents) : base(repoRootPath, path)
    {
        Contents = contents;
        _originalContentsText = GetContentsString(contents);
    }

    public void Update(T contents)
    {
        Contents = contents;
    }

    public override async Task<bool> SaveAsync()
    {
        var currentContentsText = GetContentsString(Contents);

        if (!HasAnyNonWhitespaceChanges(_originalContentsText, currentContentsText))
        {
            return false;
        }

        await File.WriteAllTextAsync(Path, currentContentsText);
        _originalContentsText = currentContentsText;
        return true;
    }

    protected abstract string GetContentsString(T contents);

    private static bool HasAnyNonWhitespaceChanges(string oldText, string newText)
    {
        // Ignore white space
        oldText = WhitespaceRegex().Replace(oldText, string.Empty);
        newText = WhitespaceRegex().Replace(newText, string.Empty);

        var diffBuilder = new InlineDiffBuilder(new Differ());
        var diff = diffBuilder.BuildDiffModel(oldText, newText);
        foreach (var line in diff.Lines)
        {
            if (line.Type is ChangeType.Inserted ||
                line.Type is ChangeType.Deleted ||
                line.Type is ChangeType.Modified)
            {
                return true;
            }
        }

        return false;
    }

    [GeneratedRegex("\\s+")]
    private static partial Regex WhitespaceRegex();
}
