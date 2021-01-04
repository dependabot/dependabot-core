module github.com/dependabot/vgotest/root

go 1.15

require (
	github.com/dependabot/vgotest/common v1.0.0
	rsc.io/qr v0.1.0
)

replace github.com/dependabot/vgotest/common => ./common
