---
applyTo: "nuget/helpers/lib/NuGetUpdater/**"
---

# NuGet Local Development Exception

NuGet C# development under `nuget/helpers/lib/NuGetUpdater` is an exception to the repository's Docker-only rule.
When a compatible .NET SDK is installed, build and test the C# projects directly on the host:

```bash
dotnet build nuget/helpers/lib/NuGetUpdater/NuGetUpdater.slnx
dotnet test nuget/helpers/lib/NuGetUpdater/NuGetUpdater.Core.Test/NuGetUpdater.Core.Test.csproj
```
