using Microsoft.Language.Xml;

namespace NuGetUpdater.Core.Updater
{
    internal class SpecialImportsConditionPatcher : IDisposable
    {
        private readonly List<string?> _capturedConditions = new List<string?>();
        private readonly XmlFilePreAndPostProcessor _processor;

        private readonly HashSet<string> ImportedFilesToIgnore = new(StringComparer.OrdinalIgnoreCase)
        {
            "Microsoft.TextTemplating.targets",
            "Microsoft.WebApplication.targets"
        };

        public SpecialImportsConditionPatcher(string projectFilePath)
        {
            _processor = new XmlFilePreAndPostProcessor(
                getContent: () => File.ReadAllText(projectFilePath),
                setContent: s => File.WriteAllText(projectFilePath, s),
                nodeFinder: doc => doc.Descendants()
                    .Where(e => e.Name == "Import")
                    .Where(e =>
                    {
                        var projectPath = e.GetAttributeValue("Project");
                        if (projectPath is not null)
                        {
                            var projectFileName = Path.GetFileName(projectPath.NormalizePathToUnix());
                            return ImportedFilesToIgnore.Contains(projectFileName);
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
