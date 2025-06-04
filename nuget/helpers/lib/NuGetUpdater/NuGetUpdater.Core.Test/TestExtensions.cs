using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core.Test;

static class TestExtensions
{
    public static XElement ToXElement(this IXmlElementSyntax xml) => XElement.Parse(xml.ToFullString());

    public static Dictionary<string, XElement> ToXElementDictionary(this Dictionary<string, IXmlElementSyntax> dictionary)
        => dictionary.ToDictionary(kvp => kvp.Key, kvp => kvp.Value.ToXElement());
}
