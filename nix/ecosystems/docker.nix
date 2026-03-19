# docker.nix: Docker ecosystem image — core + cosign + regctl binaries.
# Mirrors docker/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  # Install cosign and regctl at /opt/bin
  dockerTools = pkgs.runCommand "docker-ecosystem-tools" { } ''
    mkdir -p $out/opt/bin
    cp ${pkgs.cosign}/bin/cosign $out/opt/bin/cosign
    cp ${pkgs.regctl}/bin/regctl $out/opt/bin/regctl
    chmod +x $out/opt/bin/cosign $out/opt/bin/regctl
  '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "docker";
  tag = "docker";
  toolchainPackages = [
    pkgs.cosign
    pkgs.regctl
  ];
  extraCopyToRoot = [ dockerTools ];
  envVars = [
    "PATH=/opt/bin:/home/dependabot/bin:$PATH"
  ];
}
