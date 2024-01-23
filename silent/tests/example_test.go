package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"reflect"
	"rsc.io/script"
	"rsc.io/script/scripttest"
	"strings"
	"testing"
	"time"
)

func TestDependabot(t *testing.T) {
	ctx := context.Background()
	engine := &script.Engine{
		Conds: scripttest.DefaultConds(),
		Cmds:  Commands(),
		Quiet: !testing.Verbose(),
	}
	env := []string{
		"PATH=" + os.Getenv("PATH"),
	}
	scripttest.Test(t, ctx, engine, env, "testdata/*.txt")
}

// Commands returns the commands that can be used in the scripts.
// Each line of the scripts are <command> <args...>
// When you use "echo" in the scripts it's actually running script.Echo
// not the echo binary on your system.
func Commands() map[string]script.Cmd {
	commands := scripttest.DefaultCmds()

	// additional Dependabot commands
	commands["dependabot"] = script.Program("dependabot", nil, 100*time.Millisecond)
	commands["pr-created"] = PRCreated()
	commands["pr-updated"] = PRUpdated()

	return commands
}

type CreatePR struct {
	Type string `json:"type"`
	Data struct {
		UpdatedDependencyFiles []DependencyFile `json:"updated-dependency-files"`
	} `json:"data"`
}

type DependencyFile struct {
	Name      string `json:"name"`
	Content   string `json:"content"`
	Deleted   bool   `json:"deleted"`
	Directory string `json:"directory"`
	Operation string `json:"operation"`
}

func PRCreated() script.Cmd {
	return script.Command(
		script.CmdUsage{
			Summary: "find lines in the stderr buffer that match a pattern",
			Args:    "pr <file1> [<file2>...]",
			Detail: []string{
				"Asserts a PR was created that has content that matches the given files.",
			},
			RegexpArgs: nil,
		}, prChecker("create_pull_request"))
}

func PRUpdated() script.Cmd {
	return script.Command(
		script.CmdUsage{
			Summary: "find lines in the stderr buffer that match a pattern",
			Args:    "pr <file1> [<file2>...]",
			Detail: []string{
				"Asserts a PR was created that has content that matches the given files.",
			},
			RegexpArgs: nil,
		}, prChecker("update_pull_request"))
}

func prChecker(prType string) func(s *script.State, args ...string) (script.WaitFunc, error) {
	return func(s *script.State, args ...string) (script.WaitFunc, error) {
		expected := []any{}
		for _, arg := range args {
			f, err := os.Open(s.Path(arg))
			if err != nil {
				return nil, fmt.Errorf("failed to read file %s: %w", arg, err)
			}
			var expect any
			if err = json.NewDecoder(f).Decode(&expect); err != nil {
				return nil, fmt.Errorf("failed to decode expected file %s: %w", arg, err)
			}
			expected = append(expected, expect)
		}
		if len(expected) == 0 {
			return nil, fmt.Errorf("no files provided")
		}

		scanner := bufio.NewScanner(strings.NewReader(s.Stdout()))
		var totalPRsCreated int
		for scanner.Scan() {
			var pr CreatePR
			err := json.Unmarshal([]byte(scanner.Text()), &pr)
			if err != nil {
				return nil, fmt.Errorf("failed to decode line %s: %w", scanner.Text(), err)
			}
			if pr.Type != prType {
				continue
			}

			totalPRsCreated++
			if len(pr.Data.UpdatedDependencyFiles) == 0 {
				return nil, fmt.Errorf("no updated dependency files")
			}
			if len(pr.Data.UpdatedDependencyFiles) != len(args) {
				continue
			}

			var prsFound int
			for _, file := range pr.Data.UpdatedDependencyFiles {
				var actual any
				if err = json.Unmarshal([]byte(file.Content), &actual); err != nil {
					return nil, fmt.Errorf("failed to decode actual file %s: %w", file.Name, err)
				}
				found := false
				for _, expect := range expected {
					if reflect.DeepEqual(actual, expect) {
						prsFound++
						found = true
						break
					}
				}
				if !found {
					break
				}
			}
			if prsFound == len(args) {
				return nil, nil
			}
		}

		if totalPRsCreated > 0 {
			if prType == "create_pull_request" {
				return nil, fmt.Errorf("%v PRs created but none matched", totalPRsCreated)
			} else {
				return nil, fmt.Errorf("%v PRs updated but none matched", totalPRsCreated)
			}
		} else {
			if prType == "create_pull_request" {
				return nil, fmt.Errorf("no PR created")
			} else {
				return nil, fmt.Errorf("no PR updated")
			}
		}
	}
}
