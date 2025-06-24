using System.Collections.Immutable;

using Microsoft.Language.Xml;

using NuGetUpdater.Core.Utilities;

namespace NuGetUpdater.Core.Updater
{
    internal class SpecialImportsConditionPatcher : IDisposable
    {
        private readonly List<string?> _capturedConditions = new List<string?>();
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
                    _capturedConditions.Add(element.GetAttributeValue("Condition"));
                    return (XmlNodeSyntax)element.RemoveAttributeByName("Condition").WithAttribute("Condition", "false");
                },
                postProcessor: (i, n) =>
                {
                    var element = (IXmlElementSyntax)n;
                    var newElement = element.RemoveAttributeByName("Condition");
                    var capturedCondition = _capturedConditions[i];
                    if (capturedCondition is not null)
                    {
                        newElement = newElement.WithAttribute("Condition", capturedCondition);
                    }

                    return (XmlNodeSyntax)newElement;
                }
            );
        }

        public void Dispose()
        {
            _processor.Dispose();
        }
    }
}
