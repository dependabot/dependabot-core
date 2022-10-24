module unknown/vcs/go

go 1.12

require (
	unknown.doesnotexist/vcs v0.0.0-00010101000000-000000000000
)

replace (
	unknown.doesnotexist/vcs => ../monorepo/common
)
