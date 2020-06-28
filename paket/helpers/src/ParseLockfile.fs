namespace Dependabot

module ParseDepedenciesAndLockFile =
  open System
  open System.IO
  open Newtonsoft.Json

  type ParseDepedenciesAndLockFileArgs = {
    [<JsonProperty("dependencyPath")>]
    DependencyPath : string
  }

  type Output = {
    [<JsonProperty("groupName")>]
    GroupName : string
    [<JsonProperty("packageName")>]
    PackageName : string
    [<JsonProperty("packageVersion")>]
    PackageVersion: string
    [<JsonProperty("packageRequirement")>]
    PackageRequirement : string
  }

  let parseDepedenciesAndLockFile (args : ParseDepedenciesAndLockFileArgs) =
    let depFile =
      Path.Combine(args.DependencyPath, "paket.dependencies")
      |> File.ReadAllLines
      |> Paket.DependenciesFileParser.parseDependenciesFile "paket.dependencies" false
      |> Paket.DependenciesFile

    depFile.FindLockFile().FullName
    |> System.IO.File.ReadAllLines
    |> Paket.LockFileParser.Parse
    |> List.collect(fun x ->
        x.Packages
        |> List.map(fun p ->
          let requirement =
            try
              let requireInfo = depFile.GetPackage(x.GroupName, p.Name)
              let requirementString = requireInfo.VersionRequirement.ToString()
              if String.IsNullOrEmpty requirementString then null
              else requirementString
            with e ->
              null
          { GroupName = x.GroupName.Name
            PackageName = p.Name.Name
            PackageVersion = p.Version.Normalize()
            PackageRequirement= requirement }
        )
    )
