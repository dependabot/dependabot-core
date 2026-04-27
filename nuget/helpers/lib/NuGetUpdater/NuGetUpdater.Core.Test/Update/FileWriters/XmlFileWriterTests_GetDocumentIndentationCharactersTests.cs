using NuGetUpdater.Core.Updater.FileWriters;

using Xunit;

namespace NuGetUpdater.Core.Test.Update.FileWriters;

public class XmlFileWriterTests_GetDocumentIndentationCharactersTests
{
    [Theory]
    [MemberData(nameof(GetDocumentationIndentationCharactersTestData))]
    public async Task GetDocumentIndentationCharacters(string documentContents, string expectedIndentation)
    {
        var fileName = "project.csproj";
        using var tempDir = await TemporaryDirectory.CreateWithContentsAsync((fileName, documentContents));
        var documentSyntax = await XmlFileWriter.ReadFileContentsAsync(new DirectoryInfo(tempDir.DirectoryPath), fileName);
        var actualIndentation = XmlFileWriter.GetDocumentIndentationCharacters(documentSyntax);
        Assert.Equal(expectedIndentation, actualIndentation);
    }

    public static IEnumerable<object[]> GetDocumentationIndentationCharactersTestData()
    {
        var tb = '\t';

        //
        // common scenarios
        //

        // two spaces
        yield return [
            // documentContents
            """
            <Project>
              <PropertyGroup>
                <TargetFramework>net5.0</TargetFramework>
              </PropertyGroup>
            </Project>
            """,
            // expectedIndentation
            "  "
        ];

        // four spaces
        yield return [
            // documentContents
            """
            <Project>
                <PropertyGroup>
                    <TargetFramework>net5.0</TargetFramework>
                </PropertyGroup>
            </Project>
            """,
            // expectedIndentation
            "    "
        ];

        //
        // less common
        //

        // one tab
        yield return [
            // documentContents
            $"""
            <Project>
            {tb}<PropertyGroup>
            {tb}{tb}<TargetFramework>net5.0</TargetFramework>
            {tb}</PropertyGroup>
            </Project>
            """,
            // expectedIndentation
            "\t"
        ];

        //
        // uncommon but still valid
        //

        // one space
        yield return [
            // documentContents
            """
            <Project>
             <PropertyGroup>
              <TargetFramework>net5.0</TargetFramework>
             </PropertyGroup>
            </Project>
            """,
            // expectedIndentation
            " "
        ];

        // three spaces
        yield return [
            // documentContents
            """
            <Project>
               <PropertyGroup>
                  <TargetFramework>net5.0</TargetFramework>
               </PropertyGroup>
            </Project>
            """,
            // expectedIndentation
            "   "
        ];

        // two tabs
        yield return [
            // documentContents
            $"""
            <Project>
            {tb}{tb}<PropertyGroup>
            {tb}{tb}{tb}{tb}<TargetFramework>net5.0</TargetFramework>
            {tb}{tb}</PropertyGroup>
            </Project>
            """,
            // expectedIndentation
            "\t\t"
        ];
    }
}
