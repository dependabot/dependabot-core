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

    public IXmlElementSyntax ProjectNode => Contents.RootSyntax;

    public IEnumerable<IXmlElementSyntax> SdkNodes => ProjectNode
        .GetElements("Sdk", StringComparison.OrdinalIgnoreCase);

    public IEnumerable<IXmlElementSyntax> ImportNodes => ProjectNode
        .GetElements("Import", StringComparison.OrdinalIgnoreCase);

    public IEnumerable<IXmlElementSyntax> PropertyNodes => ProjectNode
        .GetElements("PropertyGroup", StringComparison.OrdinalIgnoreCase)
        .SelectMany(e => e.Elements);

    public IEnumerable<KeyValuePair<string, string>> GetProperties() => PropertyNodes
        .Select(e => new KeyValuePair<string, string>(e.Name, e.GetContentValue()));

    public IEnumerable<IXmlElementSyntax> ItemNodes => ProjectNode
        .GetElements("ItemGroup", StringComparison.OrdinalIgnoreCase)
        .SelectMany(e => e.Elements);

    public IEnumerable<IXmlElementSyntax> PackageItemNodes => ItemNodes.Where(e =>
        e.Name.Equals("PackageReference", StringComparison.OrdinalIgnoreCase) ||
        e.Name.Equals("GlobalPackageReference", StringComparison.OrdinalIgnoreCase) ||
        e.Name.Equals("PackageVersion", StringComparison.OrdinalIgnoreCase));

    public IEnumerable<Dependency> GetDependencies()
    {
        var sdkDependencies = GetSdkDependencies();
        var packageDependencies = PackageItemNodes
            .SelectMany(e => GetPackageDependencies(e) ?? Enumerable.Empty<Dependency>())
            .OfType<Dependency>();
        return sdkDependencies.Concat(packageDependencies);
    }

    private IEnumerable<Dependency> GetSdkDependencies()
    {
        List<Dependency> dependencies = [];
        if (ProjectNode.GetAttributeValueCaseInsensitive("Sdk") is string sdk)
        {
            dependencies.Add(GetMSBuildSdkDependency(sdk));
        }

        foreach (var sdkNode in SdkNodes)
        {
            var name = sdkNode.GetAttributeValueCaseInsensitive("Name");
            var version = sdkNode.GetAttributeValueCaseInsensitive("Version");

            if (name is not null)
            {
                dependencies.Add(GetMSBuildSdkDependency(name, version));
            }
        }

        foreach (var importNode in ImportNodes)
        {
            var name = importNode.GetAttributeValueCaseInsensitive("Name");
            var version = importNode.GetAttributeValueCaseInsensitive("Version");

            if (name is not null)
            {
                dependencies.Add(GetMSBuildSdkDependency(name, version));
            }
        }

        return dependencies;
    }

    private static Dependency GetMSBuildSdkDependency(string name, string? version = null)
    {
        var parts = name.Split('/');
        return parts.Length == 2
            ? new Dependency(parts[0], parts[1], DependencyType.MSBuildSdk)
            : new Dependency(name, version, DependencyType.MSBuildSdk);
    }

    private static IEnumerable<Dependency>? GetPackageDependencies(IXmlElementSyntax element)
    {
        List<Dependency> dependencies = [];
        var isUpdate = false;

        var name = element.GetAttributeOrSubElementValue("Include", StringComparison.OrdinalIgnoreCase)?.Trim();
        if (name is null)
        {
            isUpdate = true;
            name = element.GetAttributeOrSubElementValue("Update", StringComparison.OrdinalIgnoreCase)?.Trim();
        }

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

        dependencies.AddRange(
            name.Split(';', StringSplitOptions.RemoveEmptyEntries)
                .Select(dep => new Dependency(
                        Name: dep.Trim(),
                        Version: string.IsNullOrEmpty(version) ? null : version,
                        Type: GetDependencyType(element.Name),
                        IsUpdate: isUpdate,
                        IsOverride: isVersionOverride))
        );


        return dependencies;
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
