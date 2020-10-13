module github.com/dependabot/dependabot-core/go_modules/helpers

go 1.13

require (
	github.com/Masterminds/vcs v1.13.1
	github.com/dependabot/dependabot-core/go_modules/helpers/updater v0.0.0
	github.com/dependabot/gomodules-extracted v1.2.0
	golang.org/x/mod v0.3.0
)

replace github.com/dependabot/dependabot-core/go_modules/helpers/importresolver => ./importresolver

replace github.com/dependabot/dependabot-core/go_modules/helpers/updater => ./updater

replace github.com/dependabot/dependabot-core/go_modules/helpers/updatechecker => ./updatechecker
