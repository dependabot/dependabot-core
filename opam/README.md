# Dependabot OCaml opam Support

This package provides Dependabot support for OCaml projects using opam package manager.

## Features

- Parses `opam` and `*.opam` files
- Detects dependency updates from opam repository
- Updates opam files with new dependency versions
- Supports version constraints in opam format

## Supported Files

- `opam` - Main package definition file
- `*.opam` - Named package definition files (e.g., `mypackage.opam`)
- `opam.lock` - Lock files (future support)

## Version Format

OCaml opam uses a Debian-style versioning scheme with support for:
- Basic versions: `1.0.0`, `2.5.1`
- Pre-releases: `1.0~beta`, `1.0~rc1`
- Development versions: `dev`, `trunk`

## Dependencies

Opam files specify dependencies in the `depends:` field using package formulas:

```opam
depends: [
  "ocaml" {>= "4.08.0"}
  "dune" {>= "2.0"}
  "lwt" {>= "5.0.0" & < "6.0.0"}
]
```

## Beta Support

This ecosystem is currently in beta. Enable it with the `allow_beta_ecosystems?` feature flag.
