using System.Collections.Immutable;

using Microsoft.Language.Xml;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Updater
{
    internal class SpecialImportsConditionPatcher : IDisposable
    {
        private readonly List<IXmlElementSyntax> _capturedElements = [];
        private readonly XmlFilePreAndPostProcessor _processor;

        // These files only ship with a full Visual Studio install
        private readonly HashSet<string> ImportedFilesToIgnore = new(StringComparer.OrdinalIgnoreCase)
        {
            "Microsoft.TextTemplating.targets",
            "Microsoft.WebApplication.targets"
        };

        // PackageReference elements with `GeneratePathProperty="true"` will cause a special property to be created.
        private readonly ImmutableArray<string> PathSegmentsToIgnore =
        [
            "$(Pkg"
        ];

        public SpecialImportsConditionPatcher(string projectFilePath)
        {
            var hasBOM = false;
            _processor = new XmlFilePreAndPostProcessor(
                getContent: () =>
                {
                    var content = File.ReadAllText(projectFilePath);
                    var rawContent = File.ReadAllBytes(projectFilePath);
                    hasBOM = rawContent.HasBOM();
                    return content;
                },
                setContent: content =>
                {
                    var rawContent = content.SetBOM(hasBOM);
                    File.WriteAllBytes(projectFilePath, rawContent);
                },
                nodeFinder: doc => doc.Descendants()
                    .Where(e => e.Name == "Import")
                    .Where(e =>
                    {
                        var projectPath = e.GetAttributeValue("Project");
                        if (projectPath is not null)
                        {
                            var normalizedProjectPath = projectPath.NormalizePathToUnix();
                            var projectFileName = Path.GetFileName(normalizedProjectPath);
                            var hasForbiddenFile = ImportedFilesToIgnore.Contains(projectFileName);
                            var hasForbiddenPathSegment = PathSegmentsToIgnore.Any(p => normalizedProjectPath.Contains(p, StringComparison.OrdinalIgnoreCase));
                            return hasForbiddenFile || hasForbiddenPathSegment;
                        }

                        return false;
                    })
                    .Cast<XmlNodeSyntax>(),
                preProcessor: (i, n) =>
                {
                    var element = (IXmlElementSyntax)n;
                    _capturedElements.Add(element);
                    return (XmlNodeSyntax)element.RemoveAttributeByName("Condition").WithAttribute("Condition", "false");
                },
                postProcessor: (i, n) =>
                {
                    var element = (IXmlElementSyntax)n;
                    var originalElement = _capturedElements[i];

                    // copy over attribute values from the potentially updated element EXCEPT for `Condition="false"`
                    var updatedAttributeValues = element.Attributes.ToDictionary(e => e.Name, e => e.Value);
                    var originalRestoredElement = originalElement;
                    foreach (var (attributeName, attributeValue) in updatedAttributeValues)
                    {
                        if (attributeName == "Condition" && attributeValue == "false")
                        {
                            // this was the attribute we manually patched so it shouldn't be copied over
                            continue;
                        }

                        var oldAttribute = originalRestoredElement.GetAttribute(attributeName);
                        var updatedAttribute = oldAttribute.WithValue(updatedAttributeValues[attributeName]);
                        originalRestoredElement = originalRestoredElement.ReplaceAttribute(oldAttribute, updatedAttribute);
                    }

                    return (XmlNodeSyntax)originalRestoredElement;
                }
            );
        }

        public void Dispose()
        {
            _processor.Dispose();
        }
    }
}
