extern alias CoreV2;

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Xml.Linq;

using CoreV2::NuGet.Runtime;

using Microsoft.Language.Xml;

using NuGet.ProjectManagement;

using Runtime_AssemblyBinding = CoreV2::NuGet.Runtime.AssemblyBinding;

namespace NuGetUpdater.Core;

internal static class BindingRedirectManager
{
    private static readonly XName AssemblyBindingName = AssemblyBinding.GetQualifiedName("assemblyBinding");
    private static readonly XName DependentAssemblyName = AssemblyBinding.GetQualifiedName("dependentAssembly");
    private static readonly XName BindingRedirectName = AssemblyBinding.GetQualifiedName("bindingRedirect");

    public static async ValueTask UpdateBindingRedirectsAsync(ProjectBuildFile projectBuildFile)
    {
        var configFile = await TryGetRuntimeConfigurationFile(projectBuildFile);
        if (configFile is null)
        {
            // no runtime config file so no need to add binding redirects
            return;
        }

        var references = ExtractReferenceElements(projectBuildFile);
        references = ToAbsolutePaths(references, projectBuildFile.Path);

        var bindings = BindingRedirectResolver.GetBindingRedirects(projectBuildFile.Path, references.Select(static x => x.Include));
        if (!bindings.Any())
        {
            // no bindings to update
            return;
        }

        var fileContent = AddBindingRedirects(configFile, bindings);
        configFile = configFile with { Content = fileContent };

        await File.WriteAllTextAsync(configFile.Path, configFile.Content);

        if (configFile.ShouldAddToProject)
        {
            AddConfigFileToProject(projectBuildFile, configFile);
        }

        return;

        static List<(string Include, string HintPath)> ExtractReferenceElements(ProjectBuildFile projectBuildFile)
        {
            var document = projectBuildFile.Contents;
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

        static void AddConfigFileToProject(ProjectBuildFile projectBuildFile, ConfigurationFile configFile)
        {
            var projectNode = projectBuildFile.Contents.RootSyntax;
            var itemGroup = XmlExtensions.CreateOpenCloseXmlElementSyntax("ItemGroup")
                .AddChild(
                    XmlExtensions.CreateSingleLineXmlElementSyntax("None")
                        .WithAttribute("Include", Path.GetRelativePath(Path.GetDirectoryName(projectBuildFile.Path)!, configFile.Path)));

            var updatedProjectNode = projectNode.AddChild(itemGroup);
            var updatedXml = projectBuildFile.Contents.ReplaceNode(projectNode.AsNode, updatedProjectNode.AsNode);
            projectBuildFile.Update(updatedXml);
        }

        static List<(string Include, string HintPath)> ToAbsolutePaths(List<(string Include, string HintPath)> references, string projectPath)
        {
            var directoryPath = Path.GetDirectoryName(projectPath);
            ArgumentNullException.ThrowIfNull(directoryPath, nameof(directoryPath));
            return references.Select(t => (t.Include, Path.GetFullPath(Path.Combine(directoryPath, t.HintPath)))).ToList();
        }
    }

    private static async ValueTask<ConfigurationFile?> TryGetRuntimeConfigurationFile(ProjectBuildFile projectBuildFile)
    {
        var directoryPath = Path.GetDirectoryName(projectBuildFile.Path);
        if (directoryPath is null)
        {
            return null;
        }

        var configFile = projectBuildFile.ItemNodes
            .Where(IsConfigFile)
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

        static bool IsConfigFile(IXmlElementSyntax element)
        {
            var content = GetContent(element);
            if (content is null)
            {
                return false;
            }

            var path = Path.GetFileName(content);
            return (element.Name == "None" && string.Equals(path, "app.config", StringComparison.OrdinalIgnoreCase))
                   || (element.Name == "Content" && string.Equals(path, "web.config", StringComparison.OrdinalIgnoreCase));
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

    private static string AddBindingRedirects(ConfigurationFile configFile, IEnumerable<Runtime_AssemblyBinding> bindingRedirects)
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
        var currentBindings = GetAssemblyBindings(runtime);

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

        return String.Concat(
            document.Declaration?.ToString() ?? String.Empty, // Ensure that the <?xml> declaration node is preserved
            document.ToString()
        );

        static XDocument GetConfiguration(string configFileContent)
        {
            try
            {
                return XDocument.Parse(configFileContent, LoadOptions.PreserveWhitespace);
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
            Runtime_AssemblyBinding newBindingRedirect)
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

        static Dictionary<(string Name, string PublicKeyToken), XElement> GetAssemblyBindings(XElement runtime)
        {
            var dependencyAssemblyElements = runtime.Elements(AssemblyBindingName)
                .Elements(DependentAssemblyName);

            // We're going to need to know which element is associated with what binding for removal
            var assemblyElementPairs = dependencyAssemblyElements.Select(dependentAssemblyElement => new
            {
                Binding = Runtime_AssemblyBinding.Parse(dependentAssemblyElement),
                Element = dependentAssemblyElement
            });

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
    }
}
