namespace NuGetUpdater.Core;

public interface ILogger
{
    void LogRaw(string message);
}

public static class LoggerExtensions
{
    public static void Info(this ILogger logger, string message) => logger.LogWithLevel("INFO", message);
    public static void Warn(this ILogger logger, string message) => logger.LogWithLevel("WARN", message);
    public static void Error(this ILogger logger, string message) => logger.LogWithLevel("ERROR", message);

    private static void LogWithLevel(this ILogger logger, string level, string message) => logger.LogRaw($"{GetCurrentTimestamp()} {level} {message}");
    private static string GetCurrentTimestamp() => DateTime.UtcNow.ToString("yyyy/MM/dd HH:mm:ss");
}
