using Microsoft.Language.Xml;

namespace NuGetUpdater.Core.Updater
{
    internal class WebApplicationTargetsConditionPatcher : IDisposable
    {
        private string? _capturedCondition;
        private readonly XmlFilePreAndPostProcessor _processor;

        public WebApplicationTargetsConditionPatcher(string projectFilePath)
        {
            _processor = new XmlFilePreAndPostProcessor(
                getContent: () => File.ReadAllText(projectFilePath),
                setContent: s => File.WriteAllText(projectFilePath, s),
                nodeFinder: doc => doc.Descendants()
                    .Where(e => e.Name == "Import")
                    .FirstOrDefault(e =>
                    {
                        var projectPath = e.GetAttributeValue("Project");
                        if (projectPath is not null)
                        {
                            var projectFileName = Path.GetFileName(projectPath.NormalizePathToUnix());
                            return projectFileName.Equals("Microsoft.WebApplication.targets", StringComparison.OrdinalIgnoreCase);
                        }

                        return false;
                    })
                    as XmlNodeSyntax,
                preProcessor: n =>
                {
                    var element = (IXmlElementSyntax)n;
                    _capturedCondition = element.GetAttributeValue("Condition");
                    return (XmlNodeSyntax)element.RemoveAttributeByName("Condition").WithAttribute("Condition", "false");
                },
                postProcessor: n =>
                {
                    var element = (IXmlElementSyntax)n;
                    var newElement = element.RemoveAttributeByName("Condition");
                    if (_capturedCondition is not null)
                    {
                        newElement = newElement.WithAttribute("Condition", _capturedCondition);
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
