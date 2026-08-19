namespace NuGetUpdater.Core.Test;

internal static class StreamExtensions
{
    public static byte[] ReadAllBytes(this Stream stream)
    {
        if (stream is MemoryStream memoryStream)
        {
            return memoryStream.ToArray();
        }

        using var ms = new MemoryStream();
        stream.CopyTo(ms);
        return ms.ToArray();
    }
}
