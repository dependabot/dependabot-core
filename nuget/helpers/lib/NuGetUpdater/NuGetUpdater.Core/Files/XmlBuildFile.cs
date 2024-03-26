using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal abstract class XmlBuildFile : BuildFile<XmlDocumentSyntax>
{
    public XmlBuildFile(string basePath, string path, XmlDocumentSyntax contents)
        : base(basePath, path, contents)
    {
    }

    protected override string GetContentsString(XmlDocumentSyntax contents)
        => contents.ToFullString();
}
