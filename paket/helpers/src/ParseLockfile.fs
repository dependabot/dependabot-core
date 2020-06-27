namespace Dependabot

module ParseLockfile =
  open Newtonsoft.Json
  type ParseLockFileArgs = {
    lockFilePath : string
  }

  let parseLockfile (args : ParseLockFileArgs) =
    System.IO.File.ReadAllLines args.lockFilePath
    |> Paket.LockFileParser.Parse
    |> Seq.map(fun x ->
      let packages =
        x.Packages
        |> Seq.map(fun p ->
          {|Name = p.Name.Name; Version = p.Version.Normalize()|}
        )
      {|
        GroupName = x.GroupName.Name
        Packages = packages
      |}
    )
    |> JsonConvert.SerializeObject
    |> printfn "%s"
