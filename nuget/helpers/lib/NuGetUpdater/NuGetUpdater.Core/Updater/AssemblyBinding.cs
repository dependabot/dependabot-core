using System.Xml.Linq;

namespace NuGetUpdater.Core.Updater;

internal class AssemblyBinding : IEquatable<AssemblyBinding>
{
    private const string Namespace = "urn:schemas-microsoft-com:asm.v1";
    private string? _oldVersion;
    private string? _culture;

    internal AssemblyBinding()
    {
    }

    public AssemblyBinding(IAssembly assembly)
    {
        Name = assembly.Name;
        PublicKeyToken = assembly.PublicKeyToken;
        NewVersion = assembly.Version.ToString();
        AssemblyNewVersion = assembly.Version;
        Culture = assembly.Culture;
    }

    public string Name { get; private set; } = string.Empty;

    public string Culture
    {
        get => _culture ?? "neutral";
        set => _culture = value;
    }

    public string PublicKeyToken { get; private set; } = string.Empty;

    public string? ProcessorArchitecture { get; private set; }

    public string NewVersion { get; private set; } = string.Empty;

    public string OldVersion
    {
        get => _oldVersion ?? "0.0.0.0-" + NewVersion;
        set => _oldVersion = value;
    }

    public Version? AssemblyNewVersion { get; private set; }

    public string? CodeBaseHref { get; private set; }
    public string? CodeBaseVersion { get; private set; }
    public string? PublisherPolicy { get; private set; }

    public XElement ToXElement()
    {
        var dependentAssembly = new XElement(GetQualifiedName("dependentAssembly"),
            new XElement(GetQualifiedName("assemblyIdentity"),
                new XAttribute("name", Name),
                new XAttribute("publicKeyToken", PublicKeyToken),
                new XAttribute("culture", Culture),
                new XAttribute("processorArchitecture", ProcessorArchitecture ?? string.Empty)),
            new XElement(GetQualifiedName("bindingRedirect"),
                new XAttribute("oldVersion", OldVersion),
                new XAttribute("newVersion", NewVersion)));

        if (!string.IsNullOrEmpty(PublisherPolicy))
        {
            dependentAssembly.Add(new XElement(GetQualifiedName("publisherPolicy"),
                new XAttribute("apply", PublisherPolicy)));
        }

        if (!string.IsNullOrEmpty(CodeBaseHref))
        {
            dependentAssembly.Add(new XElement(GetQualifiedName("codeBase"),
                new XAttribute("href", CodeBaseHref),
                new XAttribute("version", CodeBaseVersion ?? string.Empty)));
        }

        // Remove empty attributes
        foreach (var attr in dependentAssembly.Descendants().Attributes().Where(a => string.IsNullOrEmpty(a.Value)).ToList())
        {
            attr.Remove();
        }

        return dependentAssembly;
    }

    public static AssemblyBinding Parse(XContainer dependentAssembly)
    {
        ArgumentNullException.ThrowIfNull(dependentAssembly);

        var binding = new AssemblyBinding();

        var assemblyIdentity = dependentAssembly.Element(GetQualifiedName("assemblyIdentity"));
        if (assemblyIdentity != null)
        {
            binding.Name = assemblyIdentity.Attribute("name")?.Value ?? string.Empty;
            binding.Culture = assemblyIdentity.Attribute("culture")?.Value!;
            binding.PublicKeyToken = assemblyIdentity.Attribute("publicKeyToken")?.Value ?? string.Empty;
            binding.ProcessorArchitecture = assemblyIdentity.Attribute("processorArchitecture")?.Value;
        }

        var bindingRedirect = dependentAssembly.Element(GetQualifiedName("bindingRedirect"));
        if (bindingRedirect != null)
        {
            binding.OldVersion = bindingRedirect.Attribute("oldVersion")?.Value!;
            binding.NewVersion = bindingRedirect.Attribute("newVersion")?.Value ?? string.Empty;
        }

        var codeBase = dependentAssembly.Element(GetQualifiedName("codeBase"));
        if (codeBase != null)
        {
            binding.CodeBaseHref = codeBase.Attribute("href")?.Value;
            binding.CodeBaseVersion = codeBase.Attribute("version")?.Value;
        }

        var publisherPolicy = dependentAssembly.Element(GetQualifiedName("publisherPolicy"));
        if (publisherPolicy != null)
        {
            binding.PublisherPolicy = publisherPolicy.Attribute("apply")?.Value;
        }

        return binding;
    }

    public static XName GetQualifiedName(string name)
    {
        return XName.Get(name, Namespace);
    }

    public bool Equals(AssemblyBinding? other)
    {
        if (other is null) return false;
        return string.Equals(Name, other.Name, StringComparison.Ordinal) &&
               string.Equals(PublicKeyToken, other.PublicKeyToken, StringComparison.Ordinal) &&
               string.Equals(Culture, other.Culture, StringComparison.Ordinal) &&
               string.Equals(ProcessorArchitecture, other.ProcessorArchitecture, StringComparison.Ordinal);
    }

    public override bool Equals(object? obj) => obj is AssemblyBinding other && Equals(other);

    public override int GetHashCode() => HashCode.Combine(Name, PublicKeyToken, Culture, ProcessorArchitecture);

    public override string ToString() => ToXElement().ToString();
}
