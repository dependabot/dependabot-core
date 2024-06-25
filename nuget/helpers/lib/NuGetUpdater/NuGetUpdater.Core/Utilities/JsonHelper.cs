using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace NuGetUpdater.Core.Utilities
{
    internal static class JsonHelper
    {
        public static JsonDocumentOptions DocumentOptions { get; } = new JsonDocumentOptions
        {
            CommentHandling = JsonCommentHandling.Skip,
        };

        public static JsonNode? ParseNode(string content)
        {
            var node = JsonNode.Parse(content, documentOptions: DocumentOptions);
            return node;
        }

        public static string UpdateJsonProperty(string json, string[] propertyPath, string newValue, StringComparison comparisonType = StringComparison.Ordinal)
        {
            var readerOptions = new JsonReaderOptions
            {
                CommentHandling = JsonCommentHandling.Allow,
            };
            var bytes = Encoding.UTF8.GetBytes(json);
            var reader = new Utf8JsonReader(bytes, readerOptions);
            using var ms = new MemoryStream();
            var writerOptions = new JsonWriterOptions
            {
                Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
                Indented = true,
            };
            var writer = new Utf8JsonWriter(ms, writerOptions);

            var pathDepth = -1;
            var currentPath = new List<string>();
            var replaceNextToken = false;
            while (reader.Read())
            {
                if (replaceNextToken)
                {
                    // replace this specific token
                    writer.WriteStringValue(newValue);
                    replaceNextToken = false;
                }
                else
                {
                    // just mirror the token
                    switch (reader.TokenType)
                    {
                        case JsonTokenType.Comment:
                            var commentValue = reader.GetComment();
                            var commentStart = json.Substring((int)reader.TokenStartIndex, 2);
                            if (commentStart == "//")
                            {
                                // Utf8JsonWriter only supports block comments, so we have to manually inject a single line comment when appropriate
                                writer.Flush();
                                var commentPrefix = GetCurrentTokenTriviaPrefix((int)reader.TokenStartIndex, json);
                                ms.Write(Encoding.UTF8.GetBytes(commentPrefix));
                                ms.Write(Encoding.UTF8.GetBytes("//" + commentValue));
                            }
                            else
                            {
                                // let the default block comment writer handle it
                                writer.WriteCommentValue(reader.GetComment());
                            }

                            break;
                        case JsonTokenType.EndArray:
                            writer.WriteEndArray();
                            break;
                        case JsonTokenType.EndObject:
                            writer.WriteEndObject();
                            pathDepth--;
                            break;
                        case JsonTokenType.False:
                            writer.WriteBooleanValue(false);
                            break;
                        case JsonTokenType.None:
                            // do nothing
                            break;
                        case JsonTokenType.Null:
                            writer.WriteNullValue();
                            break;
                        case JsonTokenType.Number:
                            writer.WriteNumberValue(reader.GetDouble());
                            break;
                        case JsonTokenType.PropertyName:
                            writer.WritePropertyName(reader.GetString()!);
                            break;
                        case JsonTokenType.StartArray:
                            writer.WriteStartArray();
                            break;
                        case JsonTokenType.StartObject:
                            writer.WriteStartObject();
                            pathDepth++;
                            break;
                        case JsonTokenType.String:
                            writer.WriteStringValue(reader.GetString());
                            break;
                        case JsonTokenType.True:
                            writer.WriteBooleanValue(true);
                            break;
                        default:
                            throw new NotImplementedException($"Unexpected token type: {reader.TokenType}");
                    }
                }

                // see if we need to replace the next token
                if (reader.TokenType == JsonTokenType.PropertyName)
                {
                    var pathValue = reader.GetString()!;

                    // ensure the current path object is of the correct size
                    while (currentPath.Count < pathDepth + 1)
                    {
                        currentPath.Add(string.Empty);
                    }

                    while (currentPath.Count > 0 && currentPath.Count > pathDepth + 1)
                    {
                        currentPath.RemoveAt(currentPath.Count - 1);
                    }

                    currentPath[pathDepth] = pathValue;
                    if (IsPathMatch(currentPath, propertyPath, comparisonType))
                    {
                        replaceNextToken = true;
                    }
                }
            }

            writer.Flush();
            ms.Flush();
            ms.Seek(0, SeekOrigin.Begin);
            var resultBytes = ms.ToArray();
            var resultJson = Encoding.UTF8.GetString(resultBytes);

            // single line comments might have had a trailing comma appended by the property writer that we can't
            // control, so we have to manually correct for it
            var originalJsonLines = json.Split('\n').Select(l => l.TrimEnd('\r')).Where(l => !string.IsNullOrWhiteSpace(l)).ToArray();
            var updatedJsonLines = resultJson.Split('\n').Select(l => l.TrimEnd('\r')).ToArray();
            for (int i = 0; i < Math.Min(originalJsonLines.Length, updatedJsonLines.Length); i++)
            {
                var updatedLine = updatedJsonLines[i];
                if (updatedLine.EndsWith(',') && updatedLine.Contains("//", StringComparison.Ordinal) && !originalJsonLines[i].EndsWith(','))
                {
                    updatedJsonLines[i] = updatedLine[..^1];
                }
            }

            resultJson = string.Join('\n', updatedJsonLines);

            // the JSON writer doesn't properly maintain newlines, so we need to normalize everything
            resultJson = resultJson.Replace("\r\n", "\n"); // CRLF => LF
            if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            {
                resultJson = resultJson.Replace("\n", "\r\n"); // LF => CRLF
            }

            return resultJson;
        }

        private static bool IsPathMatch(List<string> currentPath, string[] expectedPath, StringComparison comparisonType) =>
            currentPath.Count == expectedPath.Length &&
            currentPath.Zip(expectedPath).All(pair => string.Compare(pair.First, pair.Second, comparisonType) == 0);

        private static string GetCurrentTokenTriviaPrefix(int tokenStartIndex, string originalJson)
        {
            var prefixStart = tokenStartIndex - 1;
            for (; prefixStart >= 0; prefixStart--)
            {
                var c = originalJson[prefixStart];
                switch (c)
                {
                    case ' ':
                    case '\t':
                        // just more whitespace; keep looking
                        break;
                    case '\r':
                    case '\n':
                        // quit at newline, modulo some special cases
                        if (c == '\n')
                        {
                            // check for preceding CR
                            if (IsPreceedingCharacterEqual(originalJson, prefixStart, '\r'))
                            {
                                prefixStart--;
                            }
                        }

                        // check for preceding comma
                        if (IsPreceedingCharacterEqual(originalJson, prefixStart, ','))
                        {
                            prefixStart--;
                        }

                        goto done;
                    default:
                        // found regular character; move forward one and quit
                        prefixStart++;
                        goto done;
                }
            }

        done:
            var prefix = originalJson.Substring(prefixStart, tokenStartIndex - prefixStart);
            return prefix;
        }

        private static bool IsPreceedingCharacterEqual(string originalText, int currentIndex, char expectedCharacter)
        {
            return currentIndex > 0
                   && currentIndex < originalText.Length
                   && originalText[currentIndex - 1] == expectedCharacter;
        }
    }
}
