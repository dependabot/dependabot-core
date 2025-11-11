module github.com/dependabot/core-test

go 1.24.0

require (
	example.com/local v1.9.8
	github.com/fatih/color v1.18.0
	rsc.io/qr v0.2.0
	rsc.io/quote v1.5.2
)

require (
	github.com/mattn/go-colorable v0.1.14 // indirect
	github.com/mattn/go-isatty v0.0.20 // indirect
	golang.org/x/sys v0.36.0 // indirect
	golang.org/x/text v0.0.0-20170915032832-14c0d48ead0c // indirect
	rsc.io/sampler v1.3.0 // indirect
)

replace example.com/local => ./local
