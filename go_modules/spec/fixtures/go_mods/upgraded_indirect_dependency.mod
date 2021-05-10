module foo

go 1.12

// gorilla/csrf v1.6.2 depends on pkg/errors v0.8.0, but here we've upgraded 
// it to v0.8.1
//
// gorilla/csrf v1.7.0 depends on pkg/errors v0.9.1, so if we upgrade it to
// that version, we no longer need pkg/errors to appear in this file as MVS
// will select v0.9.1 over v0.8.1

require (
	github.com/gorilla/csrf v1.6.2
	github.com/pkg/errors v0.8.1 // indirect
)