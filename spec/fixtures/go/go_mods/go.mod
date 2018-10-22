module github.com/dependabot/vgotest

require (
	// The actual repo is fatih/color, but including the capital
	// helps us test that we preserve caps
	github.com/fatih/Color v1.7.0
	github.com/mattn/go-colorable v0.0.9 // indirect
	github.com/mattn/go-isatty v0.0.4 // indirect
	rsc.io/quote v1.4.0
)
