module github.com/dependabot/dependabot-core/go_modules/helpers

require (
	github.com/Masterminds/vcs v1.13.0
	github.com/dependabot/dependabot-core/go_modules/helpers/updater v0.0.0
	github.com/dependabot/gomodules-extracted v0.0.0-20181020215834-1b2f850478a3
)

replace github.com/dependabot/dependabot-core/go_modules/helpers/importresolver => ./importresolver

replace github.com/dependabot/dependabot-core/go_modules/helpers/updater => ./updater

replace github.com/dependabot/dependabot-core/go_modules/helpers/updatechecker => ./updatechecker
