extern alias CoreV2;

using System.Xml.Linq;

using CoreV2::NuGet.Runtime;

using Microsoft.Language.Xml;

using NuGet.ProjectManagement;

using NuGetUpdater.Core.Utilities;

using Runtime_AssemblyBinding = CoreV2::NuGet.Runtime.AssemblyBinding;

namespace NuGetUpdater.Core;

internal static class BindingRedirectManager
{
    private static readonly XName AssemblyBindingName = AssemblyBinding.GetQualifiedName("assemblyBinding");
    private static readonly XName DependentAssemblyName = AssemblyBinding.GetQualifiedName("dependentAssembly");
    private static readonly XName BindingRedirectName = AssemblyBinding.GetQualifiedName("bindingRedirect");

    /// <summary>
    /// Updates assembly binding redirects for a project build file.
    /// </summary>
    /// <remarks>
    /// Assembly binding redirects are only applicable to projects targeting .NET Framework.
    /// .NET Framework targets can appear in SDK-style OR non-SDK-style project files, using either packages.config OR `<PackageReference>` MSBuild items.
    /// See: https://learn.microsoft.com/en-us/dotnet/framework/configure-apps/redirect-assembly-versions
    ///      https://learn.microsoft.com/en-us/nuget/resources/check-project-format
    /// </remarks>
    /// <param name="projectBuildFile">The project build file (*.xproj) to be updated</param>
    /// <param name="updatedPackageName"/>The name of the package that was updated</param>
    /// <param name="updatedPackageVersion">The version of the package that was updated</param>
    public static async ValueTask UpdateBindingRedirectsAsync(ProjectBuildFile projectBuildFile, string updatedPackageName, string updatedPackageVersion)
    {
        var configFile = await TryGetRuntimeConfigurationFile(projectBuildFile.Path);
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
            // no bindings found in the project file, nothing to update
            return;
        }

        // we need to detect what assembly references come from the newly updated package; the `HintPath` will look like
        //    ..\packages\Some.Package.1.2.3\lib\net45\Some.Package.dll
        // so we first pull out the packages sub-path, e.g., `..\packages`
        // then we add the updated package name, version, and a trailing directory separator and ensure it's a unix-style path
        //    e.g., ../packages/Some.Package/1.2.3/
        // at this point any assembly in that directory is from the updated package and will need a binding redirect
        // finally we pull out the assembly `HintPath` values for _all_ references relative to the project file in a unix-style value
        //    e.g., ../packages/Some.Other.Package/4.5.6/lib/net45/Some.Other.Package.dll
        // all of that is passed to `AddBindingRedirects()` so we can ensure binding redirects for the relevant assemblies
        var packagesDirectory = PackagesConfigUpdater.GetPathToPackagesDirectory(projectBuildFile, updatedPackageName, updatedPackageVersion, packagesConfigPath: null)!;
        var assemblyPathPrefix = Path.Combine(packagesDirectory, $"{updatedPackageName}.{updatedPackageVersion}").NormalizePathToUnix().EnsureSuffix("/");
        var assemblyPaths = references.Select(static x => x.HintPath).Select(x => Path.GetRelativePath(Path.GetDirectoryName(projectBuildFile.Path)!, x).NormalizePathToUnix()).ToList();
        var bindingsAndAssemblyPaths = bindings.Zip(assemblyPaths);
        var fileContent = AddBindingRedirects(configFile, bindingsAndAssemblyPaths, assemblyPathPrefix);
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

    private static async ValueTask<ConfigurationFile?> TryGetRuntimeConfigurationFile(string fullProjectPath)
    {
        var additionalFiles = ProjectHelper.GetAdditionalFilesFromProjectContent(fullProjectPath, ProjectHelper.PathFormat.Full);
        var configFilePath = additionalFiles
            .FirstOrDefault(p =>
            {
                var fileName = Path.GetFileName(p);
                return fileName.Equals(ProjectHelper.AppConfigFileName, StringComparison.OrdinalIgnoreCase)
                    || fileName.Equals(ProjectHelper.WebConfigFileName, StringComparison.OrdinalIgnoreCase);
            });

        if (configFilePath is null)
        {
            return null;
        }

        var configFileContents = await File.ReadAllTextAsync(configFilePath);
        return new ConfigurationFile(configFilePath, configFileContents, false);
    }

    private static string AddBindingRedirects(ConfigurationFile configFile, IEnumerable<(Runtime_AssemblyBinding Binding, string AssemblyPath)> bindingRedirectsAndAssemblyPaths, string assemblyPathPrefix)
    {
        // Do nothing if there are no binding redirects to add, bail out
        if (!bindingRedirectsAndAssemblyPaths.Any())
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

        foreach (var (bindingRedirect, assemblyPath) in bindingRedirectsAndAssemblyPaths)
        {
            // If the binding redirect already exists in config, update it. Otherwise, add it.
            var bindingAssemblyIdentity = new AssemblyIdentity(bindingRedirect.Name, bindingRedirect.PublicKeyToken);
            if (currentBindings.Contains(bindingAssemblyIdentity))
            {
                // Check if there are multiple bindings in config for this assembly and remove all but the first one.
                // Normally there should only be one binding per assembly identity unless the config is malformed, which we'll fix here like NuGet.exe would.
                var existingBindings = currentBindings[bindingAssemblyIdentity];
                if (existingBindings.Any())
                {
                    // Remove all but the first element
                    foreach (var bindingElement in existingBindings.Skip(1))
                    {
                        RemoveElement(bindingElement);
                    }

                    // Update the first one with the new binding
                    UpdateBindingRedirectElement(existingBindings.First(), bindingRedirect);
                }
            }
            else
            {
                // only add a previously missing binding redirect if it's related to the package that caused the whole update
                // this isn't strictly necessary, but can be helpful to the end user and it's easy for them to revert if they
                // don't like this particular change
                if (assemblyPath.StartsWith(assemblyPathPrefix, StringComparison.OrdinalIgnoreCase))
                {
                    // Get an assembly binding element to use
                    var assemblyBindingElement = GetAssemblyBindingElement(runtime);

                    // Add the binding to that element
                    assemblyBindingElement.AddIndented(bindingRedirect.ToXElement());
                }
            }
        }

        return string.Concat(
            document.Declaration?.ToString() ?? String.Empty, // Ensure the <?xml> declaration node is preserved, if present
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

        static ILookup<AssemblyIdentity, XElement> GetAssemblyBindings(XElement runtime)
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
            // It is possible that multiple elements exist for the same assembly identity, so use a lookup (1:*) instead of a dictionary (1:1) 
            return assemblyElementPairs.ToLookup(
                p => new AssemblyIdentity(p.Binding.Name, p.Binding.PublicKeyToken),
                p => p.Element,
                new AssemblyIdentityIgnoreCaseComparer()
            );
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

    internal sealed record AssemblyIdentity(string Name, string PublicKeyToken);

    // Case-insensitive comparer. This helps avoid creating duplicate binding redirects when there is a case form mismatch between assembly identities.
    // Especially important for PublicKeyToken which is typically lowercase (using NuGet.exe), but can also be uppercase when using other tools (e.g. Visual Studio auto-resolve assembly conflicts feature).
    internal sealed class AssemblyIdentityIgnoreCaseComparer : IEqualityComparer<AssemblyIdentity>
    {
        public bool Equals(AssemblyIdentity? x, AssemblyIdentity? y) =>
            string.Equals(x?.Name, y?.Name, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(x?.PublicKeyToken ?? "null", y?.PublicKeyToken ?? "null", StringComparison.OrdinalIgnoreCase);

        public int GetHashCode(AssemblyIdentity obj) =>
            HashCode.Combine(
                obj.Name?.ToLowerInvariant(),
                obj.PublicKeyToken?.ToLowerInvariant() ?? "null"
            );
    }
}
