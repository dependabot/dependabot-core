module github.com/dependabot/dependabot-core/go_modules/helpers

require (
	github.com/Masterminds/vcs v1.13.1
	github.com/dependabot/dependabot-core/go_modules/helpers/updater v0.0.0
	github.com/dependabot/gomodules-extracted v1.0.1-0.20190731202249-95ccb2e8e153
)

replace github.com/dependabot/dependabot-core/go_modules/helpers/importresolver => ./importresolver

replace github.com/dependabot/dependabot-core/go_modules/helpers/updater => ./updater

replace github.com/dependabot/dependabot-core/go_modules/helpers/updatechecker => ./updatechecker
