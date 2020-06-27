namespace Dependabot

module ParseLockfile =
  open System.IO
  open Newtonsoft.Json
  type ParseLockFileArgs = {
    lockFilePath : string
  }

  let parseLockfile (args : ParseLockFileArgs) =
    let path =
      if args.lockFilePath.EndsWith("paket.lock") then args.lockFilePath
      else Path.Combine(args.lockFilePath, "paket.lock" )
    System.IO.File.ReadAllLines path
    |> Paket.LockFileParser.Parse
    |> List.map(fun x ->
      let packages =
        x.Packages
        |> List.map(fun p ->
          {|Name = p.Name.Name; Version = p.Version.Normalize()|}
        )
      {|
        GroupName = x.GroupName.Name
        Packages = packages
      |}
    )
