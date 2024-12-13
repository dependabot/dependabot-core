using Xunit;

public class LinuxOnlyFactAttribute : FactAttribute
{
    public LinuxOnlyFactAttribute()
    {
        if (!OperatingSystem.IsLinux())
        {
            Skip = "This test runs only on Linux.";
        }
    }
}
