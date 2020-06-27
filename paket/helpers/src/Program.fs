namespace Dependabot

module Main =
  open System
  open Newtonsoft.Json
  open Newtonsoft.Json.Linq

  type HelperParams = {
    ``function`` : string
    args : JToken
  }

  type Output = {
    result : JToken
    error : string
  }

  let createError errorMsg = {
    result = null
    error = errorMsg
  }

  let createResult o = {
    result = JToken.FromObject o
    error = null
  }

  [<EntryPoint>]
  let main argv =

    let result =
      try
        let helperParams =
          System.Console.ReadLine()
          |> JsonConvert.DeserializeObject<HelperParams>

        match helperParams.``function`` with
        // { "function" : "parseLockfile", "args" : {"lockFilePath" : "" } }
        | "parseLockfile" ->
          helperParams.args.ToObject<ParseLockfile.ParseLockFileArgs>()
          |> ParseLockfile.parseLockfile
          |> ResizeArray
          |> box
          |> Ok
        | unknown ->
          Error (sprintf "Unknown function %s" unknown)
      with e ->
        Error e.Message
    let output, returnCode =
      match result with
      | Ok a -> createResult a, 0
      | Error e -> createError e, 1
    output
    |> JsonConvert.SerializeObject
    |> printfn "%s"
    returnCode

