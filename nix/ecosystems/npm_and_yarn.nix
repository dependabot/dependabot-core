# npm_and_yarn.nix: Node.js ecosystem image — core + Node.js + npm + pnpm + yarn + corepack.
# Mirrors npm_and_yarn/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  nodejs = pkgs.nodejs_24;
  pnpm = pkgs.pnpm;
  yarnBerry = pkgs.yarn-berry;
  corepack = pkgs.corepack;

  # Build native helpers (mirrors: RUN bash /opt/npm_and_yarn/helpers/build)
  npmHelpers =
    pkgs.runCommand "npm-and-yarn-helpers"
      {
        nativeBuildInputs = [
          nodejs
          pkgs.git
          pkgs.bashInteractive
        ];
      }
      ''
        mkdir -p $out/opt/npm_and_yarn/helpers

        # Copy helper source
        cp -rL ${src}/npm_and_yarn/helpers/. $TMPDIR/helpers/
        chmod -R u+w $TMPDIR/helpers

        export HOME=$TMPDIR
        export PATH=${nodejs}/bin:$PATH

        cd $TMPDIR/helpers
        if [ -f build ]; then
          bash build || true
        fi

        cp -rL $TMPDIR/helpers/. $out/opt/npm_and_yarn/helpers/
        chmod -R u+w $out/opt/npm_and_yarn
      '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "npm_and_yarn";
  tag = "npm";
  toolchainPackages = [
    nodejs
    pnpm
    yarnBerry
    corepack
  ];
  helperDerivation = npmHelpers;
  envVars = [
    "NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt"
    "NPM_CONFIG_AUDIT=false"
    "NPM_CONFIG_FUND=false"
    "DEPENDABOT_NATIVE_HELPERS_PATH=/opt"
  ];
}
