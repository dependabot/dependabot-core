using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Xml.Linq;

using Microsoft.Language.Xml;

using NuGet;
using NuGet.Runtime;

namespace NuGetUpdater.Core;

public static class BindingRedirectManager
{
    private static readonly XName AssemblyBindingName = AssemblyBinding.GetQualifiedName("assemblyBinding");
    private static readonly XName DependentAssemblyName = AssemblyBinding.GetQualifiedName("dependentAssembly");
    private static readonly XName BindingRedirectName = AssemblyBinding.GetQualifiedName("bindingRedirect");

    public static async ValueTask<string> UpdateBindingRedirectsAsync(string projectFileContents, string projectPath)
    {
        var document = Parser.ParseText(projectFileContents);
        var configFile = await TryGetRuntimeConfigurationFile(projectPath, document);
        if (configFile is null)
        {
            // no runtime config file so no need to add binding redirects
            return projectFileContents;
        }

        var references = ExtractReferenceElements(document);

        references = ToAbsolutePaths(references, projectPath);

        var bindings = BindingRedirectResolver.GetBindingRedirects(projectPath, references.Select(static x => x.Include));

        // no bindings to update
        if (!bindings.Any())
        {
            return projectFileContents;
        }

        var fileContent = AddBindingRedirects(configFile, bindings);
        configFile = configFile with { Content = fileContent };

        await File.WriteAllTextAsync(configFile.Path, configFile.Content);

        return !configFile.ShouldAddToProject
            ? projectFileContents
            : AddConfigFileToProject(document, projectPath, configFile);

        static List<(string Include, string HintPath)> ExtractReferenceElements(XmlDocumentSyntax document)
        {
            var hintPaths = new List<(string Include, string HintPath)>();

            foreach (var element in document.Descendants().Where(static x => x.Name == "Reference"))
            {
                // Extract Include attribute
                var includeAttribute = element.GetAttribute("Include");
                if (includeAttribute == null) continue;

                // Check for HintPath as a child element
                var hintPathElement = element.Elements.FirstOrDefault(static x => x.Name == "HintPath");
                if (hintPathElement != null)
                {
                    hintPaths.Add((includeAttribute.Value, hintPathElement.GetContentValue()));
                }

                // Check for HintPath as an attribute
                var hintPathAttribute = element.GetAttribute("HintPath");
                if (hintPathAttribute != null)
                {
                    hintPaths.Add((includeAttribute.Value, hintPathAttribute.Value));
                }
            }

            return hintPaths;
        }

        static string AddConfigFileToProject(XmlDocumentSyntax document, string projectPath, ConfigurationFile configFile)
        {
            var projectNode = document.RootSyntax.Descendants().Where(static x => x.Name == "Project").FirstOrDefault();
            var itemGroup = XmlExtensions.CreateOpenCloseXmlElementSyntax("ItemGroup")
                .AddChild(
                    XmlExtensions.CreateSingleLineXmlElementSyntax("None")
                        .WithAttribute("Include", Path.GetRelativePath(Path.GetDirectoryName(projectPath)!, configFile.Path)));

            projectNode = projectNode.AddChild(itemGroup);
            return projectNode.ToFullString();
        }

        static List<(string Include, string HintPath)> ToAbsolutePaths(List<(string Include, string HintPath)> references, string projectPath)
        {
            var directoryPath = Path.GetDirectoryName(projectPath);
            ArgumentNullException.ThrowIfNull(directoryPath, nameof(directoryPath));
            return references.Select(t => (t.Include, Path.GetFullPath(Path.Combine(directoryPath, t.HintPath)))).ToList();
        }
    }

    private static async ValueTask<ConfigurationFile?> TryGetRuntimeConfigurationFile(string projectPath, XmlDocumentSyntax document)
    {
        var directoryPath = Path.GetDirectoryName(projectPath);
        if (directoryPath is null)
        {
            return null;
        }

        var configFile = document.Descendants()
            .Where(static x => x.Name == "ItemGroup")
            .SelectMany(static x => x.Elements.Where(static x => x.Name == "None" && IsConfigFile(GetContent(x))))
            .FirstOrDefault();

        if (configFile is null)
        {
            return null;
        }

        var configFilePath = Path.GetFullPath(Path.Combine(directoryPath, GetContent(configFile)));
        var configFileContents = await File.ReadAllTextAsync(configFilePath);
        return new ConfigurationFile(configFilePath, configFileContents, false);

        static string GetContent(IXmlElementSyntax element)
        {
            var content = element.GetContentValue();
            if (!string.IsNullOrEmpty(content))
            {
                return content;
            }

            content = element.GetAttributeValue("Include");
            if (!string.IsNullOrEmpty(content))
            {
                return content;
            }

            return string.Empty;
        }

        static bool IsConfigFile(string? content)
        {
            if (content is { } notNullContent)
            {
                var path = Path.GetFileName(notNullContent);

                if (string.Equals(path, "app.config", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }

                if (string.Equals(path, "web.config", StringComparison.OrdinalIgnoreCase))
                {
                    return true;
                }
            }

            return false;
        }

        static string GetConfigFileName(XmlDocumentSyntax document)
        {
            var guidValue = document.Descendants()
                .Where(static x => x.Name == "PropertyGroup")
                .SelectMany(static x => x.Elements.Where(static x => x.Name == "ProjectGuid"))
                .FirstOrDefault()
                ?.GetContentValue();
            return guidValue switch
            {
                "{E24C65DC-7377-472B-9ABA-BC803B73C61A}" or "{349C5851-65DF-11DA-9384-00065B846F21}" => "Web.config",
                _ => "App.config"
            };
        }

        static string GenerateDefaultAppConfig(XmlDocumentSyntax document)
        {
            var frameworkVersion = GetFrameworkVersion(document);
            return $"""
            <?xml version="1.0" encoding="utf-8" ?>
            <configuration>
                <startup> 
                    <supportedRuntime version="v4.0" sku=".NETFramework,Version={frameworkVersion}" />
                </startup>
            </configuration>
            """;
        }

        static string? GetFrameworkVersion(XmlDocumentSyntax document)
        {
            return document.Descendants()
                .Where(static x => x.Name == "PropertyGroup")
                .SelectMany(static x => x.Elements.Where(static x => x.Name == "TargetFrameworkVersion"))
                .FirstOrDefault()
                ?.GetContentValue();
        }
    }

    private static string AddBindingRedirects(ConfigurationFile configFile, IEnumerable<AssemblyBinding> bindingRedirects)
    {
        // Do nothing if there are no binding redirects to add, bail out
        if (!bindingRedirects.Any())
        {
            return configFile.Content;
        }

        // Get the configuration file
        var document = GetConfiguration(configFile.Content);

        // Get the runtime element
        var runtime = document.Root?.Element("runtime");

        if (runtime == null)
        {
            // Add the runtime element to the configuration document
            runtime = new XElement("runtime");
            document.Root.AddIndented(runtime);
        }

        // Get all of the current bindings in config
        var currentBindings = GetAssemblyBindings(document);

        foreach (var bindingRedirect in bindingRedirects)
        {
            // Look to see if we already have this in the list of bindings already in config.
            if (currentBindings.TryGetValue((bindingRedirect.Name, bindingRedirect.PublicKeyToken), out var existingBinding))
            {
                UpdateBindingRedirectElement(existingBinding, bindingRedirect);
            }
            else
            {
                // Get an assembly binding element to use
                var assemblyBindingElement = GetAssemblyBindingElement(runtime);

                // Add the binding to that element
                assemblyBindingElement.AddIndented(bindingRedirect.ToXElement());
            }
        }

        return document.ToString();

        static XDocument GetConfiguration(string configFileContent)
        {
            try
            {
                return XDocument.Parse(configFileContent);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException("Error loading binging redirect configuration", ex);
            }
        }

        static void RemoveElement(XElement element)
        {
            // Hold onto the parent element before removing the element
            var parentElement = element.Parent;

            // Remove the element from the document if we find a match
            element.RemoveIndented();

            if (parentElement?.HasElements != true)
            {
                parentElement.RemoveIndented();
            }
        }

        static void UpdateBindingRedirectElement(
            XElement existingDependentAssemblyElement,
            AssemblyBinding newBindingRedirect)
        {
            var existingBindingRedirectElement = existingDependentAssemblyElement.Element(BindingRedirectName);
            // Since we've successfully parsed this node, it has to be valid and this child must exist.
            if (existingBindingRedirectElement != null)
            {
                existingBindingRedirectElement.SetAttributeValue(XName.Get("oldVersion"), newBindingRedirect.OldVersion);
                existingBindingRedirectElement.SetAttributeValue(XName.Get("newVersion"), newBindingRedirect.NewVersion);
            }
            else
            {
                // At this point, <dependentAssemblyElement> already exists, but <bindingRedirectElement> does not.
                // So, extract the <bindingRedirectElement> from the newDependencyAssemblyElement, and add it
                // to the existingDependentAssemblyElement
                var newDependentAssemblyElement = newBindingRedirect.ToXElement();
                var newBindingRedirectElement = newDependentAssemblyElement.Element(BindingRedirectName);
                existingDependentAssemblyElement.AddIndented(newBindingRedirectElement);
            }
        }

        static Dictionary<(string Name, string PublicKeyToken), XElement> GetAssemblyBindings(XDocument document)
        {
            var runtime = document.Root?.Element("runtime");

            IEnumerable<XElement> assemblyBindingElements = Enumerable.Empty<XElement>();
            if (runtime != null)
            {
                assemblyBindingElements = GetAssemblyBindingElements(runtime);
            }

            // We're going to need to know which element is associated with what binding for removal
            var assemblyElementPairs = from dependentAssemblyElement in assemblyBindingElements
                                       select new
                                       {
                                           Binding = AssemblyBinding.Parse(dependentAssemblyElement),
                                           Element = dependentAssemblyElement
                                       };

            // Return a mapping from binding to element
            return assemblyElementPairs.ToDictionary(p => (p.Binding.Name, p.Binding.PublicKeyToken), p => p.Element);
        }

        static XElement GetAssemblyBindingElement(XElement runtime)
        {
            // Pick the first assembly binding element or create one if there aren't any
            var assemblyBinding = runtime.Elements(AssemblyBindingName).FirstOrDefault();
            if (assemblyBinding is not null)
            {
                return assemblyBinding;
            }

            assemblyBinding = new XElement(AssemblyBindingName);
            runtime.AddIndented(assemblyBinding);

            return assemblyBinding;
        }

        static IEnumerable<XElement> GetAssemblyBindingElements(XElement runtime)
        {
            return runtime.Elements(AssemblyBindingName)
                .Elements(DependentAssemblyName);
        }
    }

}
