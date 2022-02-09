package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/dependabot/dependabot-core/go_modules/helpers/importresolver"
)

type HelperParams struct {
	Function string          `json:"function"`
	Args     json.RawMessage `json:"args"`
}

type Output struct {
	Error  string      `json:"error,omitempty"`
	Result interface{} `json:"result,omitempty"`
}

func main() {
	d := json.NewDecoder(os.Stdin)
	helperParams := &HelperParams{}
	if err := d.Decode(helperParams); err != nil {
		abort(err)
	}

	var (
		funcOut interface{}
		funcErr error
	)
	switch helperParams.Function {
	case "getVcsRemoteForImport":
		var args importresolver.Args
		parseArgs(helperParams.Args, &args)
		funcOut, funcErr = importresolver.VCSRemoteForImport(&args)
	default:
		abort(fmt.Errorf("unrecognised function '%s'", helperParams.Function))
	}

	if funcErr != nil {
		abort(funcErr)
	}

	output(&Output{Result: funcOut})
}

func parseArgs(data []byte, args interface{}) {
	if err := json.Unmarshal(data, args); err != nil {
		abort(err)
	}
}

func output(o *Output) {
	bytes, jsonErr := json.Marshal(o)
	if jsonErr != nil {
		log.Fatal(jsonErr)
	}

	os.Stdout.Write(bytes)
}

func abort(err error) {
	output(&Output{Error: err.Error()})
	os.Exit(1)
}
