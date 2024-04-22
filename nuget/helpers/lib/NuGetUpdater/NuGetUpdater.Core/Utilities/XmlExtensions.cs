using System;
using System.Collections.Generic;
using System.Linq;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

public static class XmlExtensions
{
    public static string? GetAttributeOrSubElementValue(this IXmlElementSyntax element, string name, StringComparison comparisonType = StringComparison.Ordinal)
    {
        var attribute = element.GetAttribute(name, comparisonType);
        if (attribute is not null)
        {
            return attribute.Value;
        }

        var subElement = element.GetElements(name, comparisonType).FirstOrDefault();
        return subElement?.GetContentValue();
    }

    public static IEnumerable<IXmlElementSyntax> GetElements(this IXmlElementSyntax element, string name, StringComparison comparisonType = StringComparison.Ordinal)
    {
        return element.Elements.Where(a => a.Name.Equals(name, comparisonType));
    }

    public static XmlAttributeSyntax? GetAttribute(this IXmlElementSyntax element, string name, StringComparison comparisonType)
    {
        return element.Attributes.FirstOrDefault(a => a.Name.Equals(name, comparisonType));
    }

    public static IXmlElementSyntax RemoveAttributeByName(this IXmlElementSyntax element, string attributeName, StringComparison comparisonType = StringComparison.Ordinal)
    {
        var attribute = element.GetAttribute(attributeName, comparisonType);
        if (attribute is null)
        {
            return element;
        }

        return element.RemoveAttribute(attribute);
    }

    public static string GetAttributeValue(this IXmlElementSyntax element, string name, StringComparison comparisonType)
    {
        return element.Attributes.First(a => a.Name.Equals(name, comparisonType)).Value;
    }

    public static XmlAttributeSyntax? GetAttributeCaseInsensitive(this IXmlElementSyntax xml, string name) => GetAttribute(xml, name, StringComparison.OrdinalIgnoreCase);

    public static string? GetAttributeValueCaseInsensitive(this IXmlElementSyntax xml, string name) => xml.GetAttributeCaseInsensitive(name)?.Value;

    public static IXmlElementSyntax WithChildElement(this IXmlElementSyntax parent, string name)
    {
        var element = CreateOpenCloseXmlElementSyntax(name);
        return parent.AddChild(element);
    }

    public static IXmlElementSyntax WithEmptyChildElement(this IXmlElementSyntax parent, string name)
    {
        var element = CreateSingleLineXmlElementSyntax(name);
        return parent.AddChild(element);
    }

    public static IXmlElementSyntax WithContent(this IXmlElementSyntax element, string text)
    {
        var textSyntax = SyntaxFactory.XmlText(SyntaxFactory.Token(null, SyntaxKind.XmlTextLiteralToken, null, text));
        return element.WithContent(SyntaxFactory.SingletonList(textSyntax));
    }

    public static IXmlElementSyntax WithAttribute(this IXmlElementSyntax parent, string name, string value)
    {
        var singleSpanceTrivia = SyntaxFactory.WhitespaceTrivia(" ");

        return parent.AddAttribute(SyntaxFactory.XmlAttribute(
            SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, null)),
            SyntaxFactory.Punctuation(SyntaxKind.EqualsToken, "=", null, null),
            SyntaxFactory.XmlString(
                SyntaxFactory.Punctuation(SyntaxKind.SingleQuoteToken, "\"", null, null),
                SyntaxFactory.XmlTextLiteralToken(value, null, null),
                SyntaxFactory.Punctuation(SyntaxKind.SingleQuoteToken, "\"", null, singleSpanceTrivia))));
    }

    public static XmlElementSyntax CreateOpenCloseXmlElementSyntax(string name, int indentation = 2, bool spaces = true)
    {
        var leadingTrivia = SyntaxFactory.WhitespaceTrivia(new string(' ', indentation));
        return CreateOpenCloseXmlElementSyntax(name, new SyntaxList<SyntaxNode>(leadingTrivia));
    }

    public static XmlElementSyntax CreateOpenCloseXmlElementSyntax(string name, SyntaxList<SyntaxNode> leadingTrivia)
    {
        var newlineTrivia = SyntaxFactory.WhitespaceTrivia(Environment.NewLine);

        return SyntaxFactory.XmlElement(
            SyntaxFactory.XmlElementStartTag(
                SyntaxFactory.Punctuation(SyntaxKind.LessThanToken, "<", leadingTrivia, default),
                SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, null)),
                new SyntaxList<XmlAttributeSyntax>(),
                SyntaxFactory.Punctuation(SyntaxKind.GreaterThanToken, ">", null, newlineTrivia)),
            new SyntaxList<SyntaxNode>(),
            SyntaxFactory.XmlElementEndTag(
                SyntaxFactory.Punctuation(SyntaxKind.LessThanSlashToken, "</", leadingTrivia, default),
                SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, null)),
                SyntaxFactory.Punctuation(SyntaxKind.GreaterThanToken, ">", null, null)));
    }

    public static XmlEmptyElementSyntax CreateSingleLineXmlElementSyntax(string name, int indentation = 2, bool spaces = true)
    {
        var leadingTrivia = SyntaxFactory.WhitespaceTrivia(new string(' ', indentation));
        var followingTrivia = SyntaxFactory.WhitespaceTrivia(Environment.NewLine);

        return CreateSingleLineXmlElementSyntax(name, new SyntaxList<SyntaxNode>(leadingTrivia), new SyntaxList<SyntaxNode>(followingTrivia));
    }

    public static XmlEmptyElementSyntax CreateSingleLineXmlElementSyntax(string name, SyntaxList<SyntaxNode> leadingTrivia, SyntaxList<SyntaxNode> trailingTrivia = default)
    {
        var singleSpanceTrivia = SyntaxFactory.WhitespaceTrivia(" ");

        return SyntaxFactory.XmlEmptyElement(
            SyntaxFactory.Punctuation(SyntaxKind.LessThanToken, "<", leadingTrivia, default),
            SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, singleSpanceTrivia)),
            attributes: new SyntaxList<SyntaxNode>(),
            SyntaxFactory.Punctuation(SyntaxKind.SlashGreaterThanToken, "/>", default, trailingTrivia));
    }

    public static IXmlElementSyntax ReplaceAttribute(this IXmlElementSyntax element, XmlAttributeSyntax oldAttribute, XmlAttributeSyntax newAttribute)
    {
        return element.WithAttributes(element.AttributesNode.Replace(oldAttribute, newAttribute));
    }

    public static IXmlElementSyntax ReplaceChildElement(this IXmlElementSyntax element, IXmlElementSyntax oldChildElement, IXmlElementSyntax newChildElement)
    {
        return element.WithContent(element.Content.Replace(oldChildElement.AsNode, newChildElement.AsNode));
    }
}
