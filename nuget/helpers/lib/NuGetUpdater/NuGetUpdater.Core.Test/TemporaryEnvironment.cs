namespace NuGetUpdater.Core.Test;

public class TemporaryEnvironment : IDisposable
{
    private readonly List<(string Name, string? Value)> _originalVariables = new();

    public TemporaryEnvironment((string Name, string Value)[] variables)
    {
        foreach (var (name, value) in variables)
        {
            _originalVariables.Add((name, Environment.GetEnvironmentVariable(name)));
            Environment.SetEnvironmentVariable(name, value);
        }
    }

    public void Dispose()
    {
        foreach (var (name, value) in _originalVariables)
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }
}
