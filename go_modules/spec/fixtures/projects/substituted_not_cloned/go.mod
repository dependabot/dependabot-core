module github.com/dependabot/vgotest/subproject

go 1.15

require (
	github.com/dependabot/vgotest/common v0.0.0
  github.com/dependabot/vgotest/cmd v0.0.0
	rsc.io/qr v0.1.0
)

// valid on a checkout, but invalid to Dependabot
replace (
  github.com/dependabot/vgotest/common => ../not-cloned/common
  github.com/dependabot/vgotest/cmd => ../not-cloned/cmd
)
