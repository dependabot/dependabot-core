using System.IO;
using System.Text.RegularExpressions;
using System.Threading.Tasks;

using DiffPlex;
using DiffPlex.DiffBuilder;
using DiffPlex.DiffBuilder.Model;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal sealed partial class BuildFile
{
    public string RepoRelativePath { get; }
    public string Path { get; }
    public XmlDocumentSyntax Xml { get; private set; }

    public XmlDocumentSyntax OriginalXml { get; private set; }

    public BuildFile(string repoRootPath, string path, XmlDocumentSyntax xml)
    {
        RepoRelativePath = System.IO.Path.GetRelativePath(repoRootPath, path);
        Path = path;
        Xml = xml;
        OriginalXml = xml;
    }

    public void Update(XmlDocumentSyntax xml)
    {
        Xml = xml;
    }

    public async Task<bool> SaveAsync()
    {
        if (OriginalXml == Xml)
        {
            return false;
        }

        var originalXmlText = OriginalXml.ToFullString();
        var xmlText = Xml.ToFullString();

        if (!HasAnyNonWhitespaceChanges(originalXmlText, xmlText))
        {
            return false;
        }

        await File.WriteAllTextAsync(Path, xmlText);
        OriginalXml = Xml;
        return true;
    }

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