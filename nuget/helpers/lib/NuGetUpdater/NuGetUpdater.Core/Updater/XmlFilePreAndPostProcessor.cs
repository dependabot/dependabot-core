using Microsoft.Language.Xml;

namespace NuGetUpdater.Core.Updater
{
    internal class XmlFilePreAndPostProcessor : IDisposable
    {
        public Func<string> GetContent { get; }
        public Action<string> SetContent { get; }
        public Func<XmlDocumentSyntax, XmlNodeSyntax?> NodeFinder { get; }
        public Func<XmlNodeSyntax, XmlNodeSyntax> PreProcessor { get; }
        public Func<XmlNodeSyntax, XmlNodeSyntax> PostProcessor { get; }

        public XmlFilePreAndPostProcessor(Func<string> getContent, Action<string> setContent, Func<XmlDocumentSyntax, XmlNodeSyntax?> nodeFinder, Func<XmlNodeSyntax, XmlNodeSyntax> preProcessor, Func<XmlNodeSyntax, XmlNodeSyntax> postProcessor)
        {
            GetContent = getContent;
            SetContent = setContent;
            NodeFinder = nodeFinder;
            PreProcessor = preProcessor;
            PostProcessor = postProcessor;
            PreProcess();
        }

        public void Dispose()
        {
            PostProcess();
        }

        private void PreProcess() => RunProcessor(PreProcessor);

        private void PostProcess() => RunProcessor(PostProcessor);

        private void RunProcessor(Func<XmlNodeSyntax, XmlNodeSyntax> processor)
        {
            var content = GetContent();
            var xml = Parser.ParseText(content);
            if (xml is null)
            {
                return;
            }

            var node = NodeFinder(xml);
            if (node is null)
            {
                return;
            }

            var replacementElement = processor(node);
            var replacementXml = xml.ReplaceNode(node, replacementElement);
            var replacementString = replacementXml.ToFullString();
            SetContent(replacementString);
        }
    }
}
