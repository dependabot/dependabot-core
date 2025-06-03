using System.Text.Json;

using NuGetUpdater.Core.Analyze;
using NuGetUpdater.Core.Discover;

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

    public static void ReportAnalysis(this ILogger logger, AnalysisResult analysisResult)
    {
        logger.Info("Analysis JSON content:");
        logger.Info(JsonSerializer.Serialize(analysisResult, AnalyzeWorker.SerializerOptions));
    }

    public static void ReportDiscovery(this ILogger logger, WorkspaceDiscoveryResult discoveryResult)
    {
        logger.Info("Discovery JSON content:");
        logger.Info(JsonSerializer.Serialize(discoveryResult, DiscoveryWorker.SerializerOptions));
    }

    private static void LogWithLevel(this ILogger logger, string level, string message) => logger.LogRaw($"{GetCurrentTimestamp()} {level} {message}");
    private static string GetCurrentTimestamp() => DateTime.UtcNow.ToString("yyyy/MM/dd HH:mm:ss");
}
