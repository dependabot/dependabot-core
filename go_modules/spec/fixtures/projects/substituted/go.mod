module github.com/dependabot/vgotest/cmd

go 1.15

require (
	github.com/dependabot/vgotest/common v1.0.0
	rsc.io/qr v0.1.0
)

// valid on a checkout, but invalid to Dependabot
replace github.com/dependabot/vgotest/common => ../monorepo/common

