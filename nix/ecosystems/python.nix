# python.nix: Python ecosystem image — core + multiple Python versions + pyenv shim.
# Mirrors python/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  # Python versions available in current nixpkgs
  pythonVersions = {
    "3.11" = pkgs.python311;
    "3.12" = pkgs.python312;
    "3.13" = pkgs.python313;
    "3.14" = pkgs.python314;
  };

  # Create pyenv-compatible directory structure with symlinks
  # The Ruby code calls `pyenv exec python3.X` so we need the shim
  pyenvShim = pkgs.runCommand "pyenv-shim" { } ''
    mkdir -p $out/usr/local/.pyenv/bin
    mkdir -p $out/usr/local/.pyenv/versions

    # Create version directories with symlinks to Nix Python installations
    ${builtins.concatStringsSep "\n" (
      builtins.attrValues (
        builtins.mapAttrs (ver: py: ''
          mkdir -p $out/usr/local/.pyenv/versions/${py.version}
          ln -s ${py}/bin $out/usr/local/.pyenv/versions/${py.version}/bin
          ln -s ${py}/lib $out/usr/local/.pyenv/versions/${py.version}/lib
          ln -s ${py}/include $out/usr/local/.pyenv/versions/${py.version}/include 2>/dev/null || true
        '') pythonVersions
      )
    )}

    # Create a minimal pyenv shim script
    cat > $out/usr/local/.pyenv/bin/pyenv <<'PYENV'
    #!/bin/bash
    # Minimal pyenv shim for Dependabot Nix images
    PYENV_ROOT="/usr/local/.pyenv"
    case "$1" in
      exec)
        shift
        cmd="$1"
        shift
        if [ -n "$PYENV_VERSION" ]; then
          exec "$PYENV_ROOT/versions/$PYENV_VERSION/bin/$cmd" "$@"
        else
          exec "$cmd" "$@"
        fi
        ;;
      versions)
        ls "$PYENV_ROOT/versions/"
        ;;
      version)
        echo "$PYENV_VERSION"
        ;;
      *)
        echo "pyenv shim: unsupported command '$1'" >&2
        exit 1
        ;;
    esac
    PYENV
    chmod +x $out/usr/local/.pyenv/bin/pyenv
  '';

  # Build Python helpers for each version
  pythonHelpers =
    pkgs.runCommand "python-helpers"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.bashInteractive
        ]
        ++ (builtins.attrValues pythonVersions);
      }
      ''
        mkdir -p $out/opt/python/helpers

        cp -rL ${src}/python/helpers/. $TMPDIR/helpers/
        chmod -R u+w $TMPDIR/helpers

        export HOME=$TMPDIR
        export PYENV_ROOT=/usr/local/.pyenv

        cp -rL $TMPDIR/helpers/. $out/opt/python/helpers/
        chmod -R u+w $out/opt/python
      '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "python";
  tag = "pip";
  toolchainPackages = builtins.attrValues pythonVersions;
  helperDerivation = pythonHelpers;
  extraCopyToRoot = [ pyenvShim ];
  envVars = [
    "PYENV_ROOT=/usr/local/.pyenv"
    "PATH=/usr/local/.pyenv/bin:/home/dependabot/bin:$PATH"
    "REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
    "DEPENDABOT_NATIVE_HELPERS_PATH=/opt"
  ];
}
