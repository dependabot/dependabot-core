namespace Dependabot

module Main =
  open System
  open Newtonsoft.Json
  open Newtonsoft.Json.Linq

  type HelperParams = {
    [<JsonProperty("function")>]
    Function : string
    [<JsonProperty("args")>]
    Args : JToken
  }

  type Output = {
    [<JsonProperty("result")>]
    Result : JToken
    [<JsonProperty("error")>]
    Error : string
  }

  let createError errorMsg = {
    Result = null
    Error = errorMsg
  }

  let createResult o = {
    Result = JToken.FromObject o
    Error = null
  }

  [<EntryPoint>]
  let main argv =

    let result =
      try
        let helperParams =
          System.Console.ReadLine()
          |> JsonConvert.DeserializeObject<HelperParams>

        match helperParams.Function with
        // { "function" : "parseDepedenciesAndLockFile", "args" : {"dependencyPath" : "" } }
        | "parseLockfile" ->
          helperParams.Args.ToObject<ParseDepedenciesAndLockFile.ParseDepedenciesAndLockFileArgs>()
          |> ParseDepedenciesAndLockFile.parseDepedenciesAndLockFile
          |> box
          |> Ok
        | unknown ->
          Error (sprintf "Unknown function %s" unknown)
      with e ->
        Error (sprintf "%A" e)
    let output, returnCode =
      match result with
      | Ok a -> createResult a, 0
      | Error e -> createError e, 1
    output
    |> JsonConvert.SerializeObject
    |> printfn "%s"
    returnCode

