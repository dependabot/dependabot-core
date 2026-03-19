# go_modules.nix: Go ecosystem image — core + Go runtime + native helpers.
# Mirrors go_modules/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  go = pkgs.go_1_26;

  # Install Go at /opt/go (matching current Dockerfile layout)
  goInstall = pkgs.runCommand "go-install" { } ''
    mkdir -p $out/opt/go/bin
    ln -s ${go}/share/go/* $out/opt/go/ 2>/dev/null || true
    ln -s ${go}/bin/go $out/opt/go/bin/go
    ln -s ${go}/bin/gofmt $out/opt/go/bin/gofmt 2>/dev/null || true
  '';

  # Build go_modules native helpers (mirrors: RUN bash /opt/go_modules/helpers/build)
  goHelpers =
    pkgs.runCommand "go-modules-helpers"
      {
        nativeBuildInputs = [
          go
          pkgs.git
          pkgs.gcc
          pkgs.gnumake
          pkgs.bashInteractive
        ];
      }
      ''
        mkdir -p $out/opt/go_modules/helpers

        # Copy helper source
        cp -rL ${src}/go_modules/helpers/. $TMPDIR/helpers/
        chmod -R u+w $TMPDIR/helpers

        export HOME=$TMPDIR
        export GOPATH=$TMPDIR/gopath
        export GOBIN=$out/opt/go_modules/bin
        export PATH=${go}/bin:$PATH
        mkdir -p $GOBIN

        cd $TMPDIR/helpers
        if [ -f build ]; then
          bash build || true
        fi

        cp -rL $TMPDIR/helpers/. $out/opt/go_modules/helpers/
        chmod -R u+w $out/opt/go_modules
      '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "go_modules";
  tag = "gomod";
  toolchainPackages = [ go ];
  helperDerivation = goHelpers;
  extraCopyToRoot = [ goInstall ];
  envVars = [
    "PATH=/opt/go/bin:/home/dependabot/bin:$PATH"
    "DEPENDABOT_NATIVE_HELPERS_PATH=/opt"
  ];
}
