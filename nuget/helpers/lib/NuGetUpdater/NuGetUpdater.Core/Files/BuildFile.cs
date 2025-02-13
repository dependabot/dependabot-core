using System.Text.RegularExpressions;

using DiffPlex;
using DiffPlex.DiffBuilder;
using DiffPlex.DiffBuilder.Model;

namespace NuGetUpdater.Core;

internal abstract class BuildFile
{
    public string BasePath { get; }
    public string Path { get; }
    public string RelativePath => System.IO.Path.GetRelativePath(BasePath, Path);
    public bool IsOutsideBasePath => RelativePath.StartsWith("..");
    public bool FailedToParse { get; protected set; }

    public BuildFile(string basePath, string path)
    {
        BasePath = basePath;
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
    internal enum EOLSpec
    {
        Unknown,
        LF,
        CR,
        CRLF
    };

    internal EOLSpec originalEOL = EOLSpec.Unknown;
    internal EOLSpec writeEOL = EOLSpec.Unknown;

    public BuildFile(string repoRootPath, string path, T contents) : base(repoRootPath, path)
    {
        Contents = contents;
        _originalContentsText = GetContentsString(contents);
        // Get stats on EOL characters/character sequences, if one predominates choose that for writing later.
        var lfcount = _originalContentsText.Count(c => c == '\n');
        var crcount = _originalContentsText.Count(c => c == '\r');
        var crlfcount = Regex.Matches(_originalContentsText, "\r\n").Count();
        lfcount -= crlfcount;
        crcount -= crlfcount;
        if (lfcount > crcount && lfcount > crlfcount)
        {
            originalEOL = EOLSpec.LF;
        }
        else if (crlfcount > crcount)
        {
            originalEOL = EOLSpec.CRLF;
        }
        else
        {
            originalEOL = EOLSpec.CR;
        }
        writeEOL = originalEOL;
    }

    public void Update(T contents)
    {
        Contents = contents;
    }

    public override async Task<bool> SaveAsync()
    {
        var currentContentsText = GetContentsString(Contents);

        if (!HasAnyNonWhitespaceChanges(_originalContentsText, currentContentsText) && originalEOL == writeEOL)
        {
            return false;
        }

        switch (writeEOL)
        {
            case EOLSpec.LF:
                currentContentsText = Regex.Replace(currentContentsText, "(\r\n|\r)", "\n");
                break;
            case EOLSpec.CR:
                currentContentsText = Regex.Replace(currentContentsText, "(\r\n|\n)", "\r");
                break;
            case EOLSpec.CRLF:
                currentContentsText = Regex.Replace(currentContentsText, "(\r\n|\r|\n)", "\r\n");
                break;
            case EOLSpec.Unknown:
            default:
                break;
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
        var diff = diffBuilder.BuildDiffModel(oldText, newText, false);
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

    [GeneratedRegex("[^\\S\r\n]+")]
    private static partial Regex WhitespaceRegex();
}
