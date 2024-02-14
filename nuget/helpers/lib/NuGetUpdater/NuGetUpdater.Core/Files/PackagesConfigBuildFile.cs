using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal sealed class PackagesConfigBuildFile : XmlBuildFile
{
    public static PackagesConfigBuildFile Open(string repoRootPath, string path)
        => Parse(repoRootPath, path, File.ReadAllText(path));

    public static PackagesConfigBuildFile Parse(string repoRootPath, string path, string xml)
        => new(repoRootPath, path, Parser.ParseText(xml));

    public PackagesConfigBuildFile(string repoRootPath, string path, XmlDocumentSyntax contents)
        : base(repoRootPath, path, contents)
    {
    }

    public IEnumerable<IXmlElementSyntax> Packages => Contents.RootSyntax.GetElements("package", StringComparison.OrdinalIgnoreCase);

    public IEnumerable<Dependency> GetDependencies() => Packages
        .Where(p => p.GetAttribute("id") is not null && p.GetAttribute("version") is not null)
        .Select(p => new Dependency(
            p.GetAttributeValue("id", StringComparison.OrdinalIgnoreCase),
            p.GetAttributeValue("version", StringComparison.OrdinalIgnoreCase),
            DependencyType.PackageConfig,
            (p.GetAttribute("developmentDependency", StringComparison.OrdinalIgnoreCase)?.Value ?? "false").Equals(true.ToString(), StringComparison.OrdinalIgnoreCase)));
}
