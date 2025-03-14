using System.Collections.Immutable;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core.Updater
{
    internal class XmlFilePreAndPostProcessor : IDisposable
    {
        public Func<string> GetContent { get; }
        public Action<string> SetContent { get; }
        public Func<XmlDocumentSyntax, IEnumerable<XmlNodeSyntax>> NodeFinder { get; }
        public Func<int, XmlNodeSyntax, XmlNodeSyntax> PreProcessor { get; }
        public Func<int, XmlNodeSyntax, XmlNodeSyntax> PostProcessor { get; }

        public XmlFilePreAndPostProcessor(Func<string> getContent, Action<string> setContent, Func<XmlDocumentSyntax, IEnumerable<XmlNodeSyntax>> nodeFinder, Func<int, XmlNodeSyntax, XmlNodeSyntax> preProcessor, Func<int, XmlNodeSyntax, XmlNodeSyntax> postProcessor)
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

        private void RunProcessor(Func<int, XmlNodeSyntax, XmlNodeSyntax> processor)
        {
            var content = GetContent();
            var xml = Parser.ParseText(content);
            if (xml is null)
            {
                return;
            }

            var offset = 0;
            var nodes = NodeFinder(xml).ToImmutableArray();
            for (int i = 0; i < nodes.Length; i++)
            {
                // modify the node...
                var node = nodes[i];
                var replacementElement = processor(i, node);

                // ...however, the XML structure we're using is immutable and calling `.ReplaceNode()` below will fail because the nodes are no longer equal
                // find the equivalent node by offset, accounting for any changes in length
                var candidateEquivalentNodes = xml.DescendantNodes().OfType<XmlNodeSyntax>().ToArray();
                var equivalentNode = candidateEquivalentNodes.First(n => n.Start == node.Start + offset);

                // do the actual replacement
                xml = xml.ReplaceNode(equivalentNode, replacementElement);

                // update our offset
                var thisNodeOffset = replacementElement.ToFullString().Length - node.ToFullString().Length;
                offset += thisNodeOffset;
            }

            var replacementString = xml.ToFullString();
            SetContent(replacementString);
        }
    }
}
