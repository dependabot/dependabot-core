namespace Dependabot

module Main =
  open System
  open Newtonsoft.Json
  open Newtonsoft.Json.Linq

  type HelperParams = {
    ``function`` : string
    args : JToken
  }

  [<EntryPoint>]
  let main argv =

    let helperParams =
      System.Console.ReadLine()
      |> JsonConvert.DeserializeObject<HelperParams>

    printfn "%A" helperParams
    match helperParams.``function`` with
    // { "function" : "parseLockfile", "args" : {"lockFilePath" : "" } }
    | "parseLockfile" ->
      helperParams.args.ToObject<ParseLockfile.ParseLockFileArgs>()
      |> ParseLockfile.parseLockfile
      0
    | unknown ->
      eprintfn "Unknown function %s" unknown
      1
