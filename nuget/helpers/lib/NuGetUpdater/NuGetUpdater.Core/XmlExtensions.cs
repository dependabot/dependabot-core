using System;

using Microsoft.Language.Xml;

namespace NuGetUpdater.Core;

public static class XmlExtensions
{
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
        return parent.AddAttribute(SyntaxFactory.XmlAttribute(
            SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, null)),
            SyntaxFactory.Punctuation(SyntaxKind.EqualsToken, "=", null, null),
            SyntaxFactory.XmlString(
                SyntaxFactory.Punctuation(SyntaxKind.SingleQuoteToken, "\"", null, null),
                SyntaxFactory.XmlTextLiteralToken(value, null, null),
                SyntaxFactory.Punctuation(SyntaxKind.SingleQuoteToken, "\"", null, null))));
    }

    public static XmlElementSyntax CreateOpenCloseXmlElementSyntax(string name, int indentation = 2, bool spaces = true)
    {
        var leadingTrivia = SyntaxFactory.WhitespaceTrivia("  ");
        var newlineTrivia = SyntaxFactory.WhitespaceTrivia(Environment.NewLine);

        return SyntaxFactory.XmlElement(
            SyntaxFactory.XmlElementStartTag(
                SyntaxFactory.Punctuation(SyntaxKind.LessThanToken, "<", leadingTrivia, null),
                SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, null)),
                new SyntaxList<XmlAttributeSyntax>(),
                SyntaxFactory.Punctuation(SyntaxKind.GreaterThanToken, ">", null, newlineTrivia)),
            new SyntaxList<SyntaxNode>(),
            SyntaxFactory.XmlElementEndTag(
                SyntaxFactory.Punctuation(SyntaxKind.LessThanSlashToken, "</", leadingTrivia, null),
                SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, null)),
                SyntaxFactory.Punctuation(SyntaxKind.GreaterThanToken, ">", null, null)));
    }

    public static XmlEmptyElementSyntax CreateSingleLineXmlElementSyntax(string name, int indentation = 2, bool spaces = true)
    {
        var leadingTrivia = SyntaxFactory.WhitespaceTrivia("  ");
        var singleSpanceTrivia = SyntaxFactory.WhitespaceTrivia(" ");
        var newlineTrivia = SyntaxFactory.WhitespaceTrivia(Environment.NewLine);
        return SyntaxFactory.XmlEmptyElement(
            SyntaxFactory.Punctuation(SyntaxKind.LessThanToken, "<", leadingTrivia, null),
            SyntaxFactory.XmlName(null, SyntaxFactory.XmlNameToken(name, null, singleSpanceTrivia)),
            attributes: new SyntaxList<SyntaxNode>(),
            SyntaxFactory.Punctuation(SyntaxKind.SlashGreaterThanToken, "/>", null, newlineTrivia));
    }
}
