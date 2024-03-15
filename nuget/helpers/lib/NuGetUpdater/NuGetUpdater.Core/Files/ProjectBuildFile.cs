using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

internal sealed class ProjectBuildFile : XmlBuildFile
{
    public static ProjectBuildFile Open(string basePath, string path)
        => Parse(basePath, path, File.ReadAllText(path));

    public static ProjectBuildFile Parse(string basePath, string path, string xml)
        => new(basePath, path, Parser.ParseText(xml));

    public ProjectBuildFile(string basePath, string path, XmlDocumentSyntax contents)
        : base(basePath, path, contents)
    {
    }

    public IEnumerable<IXmlElementSyntax> PropertyNodes => Contents.RootSyntax
        .GetElements("PropertyGroup", StringComparison.OrdinalIgnoreCase)
        .SelectMany(e => e.Elements);

    public IEnumerable<KeyValuePair<string, string>> GetProperties() => PropertyNodes
        .Select(e => new KeyValuePair<string, string>(e.Name, e.GetContentValue()));

    public IEnumerable<IXmlElementSyntax> ItemNodes => Contents.RootSyntax
        .GetElements("ItemGroup", StringComparison.OrdinalIgnoreCase)
        .SelectMany(e => e.Elements);

    public IEnumerable<IXmlElementSyntax> PackageItemNodes => ItemNodes.Where(e =>
        e.Name.Equals("PackageReference", StringComparison.OrdinalIgnoreCase) ||
        e.Name.Equals("GlobalPackageReference", StringComparison.OrdinalIgnoreCase) ||
        e.Name.Equals("PackageVersion", StringComparison.OrdinalIgnoreCase));

    public IEnumerable<Dependency> GetDependencies() => PackageItemNodes
        .Select(GetDependency)
        .OfType<Dependency>();

    private static Dependency? GetDependency(IXmlElementSyntax element)
    {
        var name = element.GetAttributeOrSubElementValue("Include", StringComparison.OrdinalIgnoreCase)
                   ?? element.GetAttributeOrSubElementValue("Update", StringComparison.OrdinalIgnoreCase);
        if (name is null || name.StartsWith("@("))
        {
            return null;
        }

        var isVersionOverride = false;
        var version = element.GetAttributeOrSubElementValue("Version", StringComparison.OrdinalIgnoreCase);
        if (version is null)
        {
            version = element.GetAttributeOrSubElementValue("VersionOverride", StringComparison.OrdinalIgnoreCase);
            isVersionOverride = version is not null;
        }

        return new Dependency(
            Name: name,
            Version: version?.Length == 0 ? null : version,
            Type: GetDependencyType(element.Name),
            IsOverride: isVersionOverride);
    }

    private static DependencyType GetDependencyType(string name)
    {
        return name.ToLower() switch
        {
            "packagereference" => DependencyType.PackageReference,
            "globalpackagereference" => DependencyType.GlobalPackageReference,
            "packageversion" => DependencyType.PackageVersion,
            _ => throw new InvalidOperationException($"Unknown dependency type: {name}")
        };
    }

    public IEnumerable<string> GetReferencedProjectPaths() => ItemNodes
        .Where(e =>
            e.Name.Equals("ProjectReference", StringComparison.OrdinalIgnoreCase) ||
            e.Name.Equals("ProjectFile", StringComparison.OrdinalIgnoreCase))
        .Select(e => PathHelper.GetFullPathFromRelative(System.IO.Path.GetDirectoryName(Path)!, e.GetAttribute("Include").Value));

    public void NormalizeDirectorySeparatorsInProject()
    {
        var hintPathNodes = Contents.Descendants()
            .Where(e =>
                e.Name.Equals("HintPath", StringComparison.OrdinalIgnoreCase) &&
                e.Parent.Name.Equals("Reference", StringComparison.OrdinalIgnoreCase))
            .Select(e => (XmlElementSyntax)e.AsNode);
        var updatedXml = Contents.ReplaceNodes(hintPathNodes,
            (_, n) => n.WithContent(n.GetContentValue().Replace("/", "\\")).AsNode);
        Update(updatedXml);
    }

    public ProjectBuildFileType GetFileType()
    {
        var extension = System.IO.Path.GetExtension(Path);
        return extension.ToLower() switch
        {
            ".csproj" => ProjectBuildFileType.Project,
            ".vbproj" => ProjectBuildFileType.Project,
            ".fsproj" => ProjectBuildFileType.Project,
            ".proj" => ProjectBuildFileType.Proj,
            ".props" => ProjectBuildFileType.Props,
            ".targets" => ProjectBuildFileType.Targets,
            _ => ProjectBuildFileType.Unknown
        };
    }
}

public enum ProjectBuildFileType
{
    Unknown,
    Proj,
    Project,
    Props,
    Targets
}
