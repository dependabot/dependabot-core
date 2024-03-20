using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal abstract class XmlBuildFile : BuildFile<XmlDocumentSyntax>
{
    public XmlBuildFile(string repoRootPath, string path, XmlDocumentSyntax contents)
        : base(repoRootPath, path, contents)
    {
    }

    protected override string GetContentsString(XmlDocumentSyntax contents)
        => contents.ToFullString();
}
