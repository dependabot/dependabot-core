using System.Text;

namespace NuGetUpdater.Core.Utilities;

internal static class BOMHandling
{
    public static bool HasBOM(this byte[] rawContent)
    {
        var bom = Encoding.UTF8.GetPreamble();
        if (rawContent.Length >= bom.Length)
        {
            for (int i = 0; i < bom.Length; i++)
            {
                if (rawContent[i] != bom[i])
                {
                    return false;
                }
            }

            return true;
        }

        return false;
    }
    public static byte[] SetBOM(this string content, bool setBOM)
    {
        var rawContent = Encoding.UTF8.GetBytes(content);
        if (setBOM)
        {
            rawContent = Encoding.UTF8.GetPreamble().Concat(rawContent).ToArray();
        }

        return rawContent;
    }
}
