namespace NuGetUpdater.Core.Utilities;

public class MarkdownListBuilder
{
    public static string FromObject(object obj)
    {
        return string.Join(Environment.NewLine, LinesFromObject(obj));
    }

    private static string[] LinesFromObject(object obj)
    {
        var lines = new List<string>();
        switch (obj)
        {
            case IDictionary<string, object> dict:
                // key1: value1
                // key2: value2
                foreach (var (key, value) in dict)
                {
                    if (key == "error-backtrace")
                    {
                        continue;
                    }

                    var childLines = LinesFromObject(value);
                    if (childLines.Length == 1)
                    {
                        // display inline
                        lines.Add($"- {key}: {childLines[0]}");
                    }
                    else
                    {
                        // display in sub-list
                        lines.Add($"- {key}:");
                        foreach (var childLine in childLines)
                        {
                            lines.Add($"  {childLine}");
                        }
                    }
                }
                break;
            case IEnumerable<object> values:
                // - value1
                // - value2
                foreach (var value in values)
                {
                    var valueLines = LinesFromObject(value);
                    lines.Add($"- {valueLines[0]}");
                    foreach (var valueLine in valueLines.Skip(1))
                    {
                        lines.Add($"  {valueLine}");
                    }
                }
                break;
            case bool b:
                lines.Add(b.ToString().ToLowerInvariant());
                break;
            default:
                lines.Add(obj.ToString()!);
                break;
        }

        return [.. lines];
    }
}
