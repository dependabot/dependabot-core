using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal sealed class PackagesConfigBuildFile : XmlBuildFile
{
    public static PackagesConfigBuildFile Open(string basePath, string path)
        => Parse(basePath, path, File.ReadAllText(path));

    public static PackagesConfigBuildFile Parse(string basePath, string path, string xml)
        => new(basePath, path, Parser.ParseText(xml));

    public PackagesConfigBuildFile(string basePath, string path, XmlDocumentSyntax contents)
        : base(basePath, path, contents)
    {
        var invalidPackageElements = Packages.Where(p => p.GetAttribute("id") is null || p.GetAttribute("version") is null).ToList();
        if (invalidPackageElements.Any())
        {
            throw new UnparseableFileException("`package` element missing `id` or `version` attributes", path);
        }
    }

    public IEnumerable<IXmlElementSyntax> Packages => Contents.RootSyntax.GetElements("package", StringComparison.OrdinalIgnoreCase);

    public IEnumerable<Dependency> GetDependencies() => Packages
        .Select(p => new Dependency(
            p.GetAttributeValue("id", StringComparison.OrdinalIgnoreCase),
            p.GetAttributeValue("version", StringComparison.OrdinalIgnoreCase),
            DependencyType.PackagesConfig,
            IsDevDependency: (p.GetAttribute("developmentDependency", StringComparison.OrdinalIgnoreCase)?.Value ?? "false").Equals(true.ToString(), StringComparison.OrdinalIgnoreCase)));
}
