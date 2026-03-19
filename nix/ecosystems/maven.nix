# maven.nix: Maven ecosystem image — core + JDK 21 + Maven.
# Mirrors maven/Dockerfile.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

let
  mavenInstall = pkgs.runCommand "maven-install" { } ''
    mkdir -p $out/usr/share/maven
    ln -s ${pkgs.maven}/share/java/maven $out/usr/share/maven/lib 2>/dev/null || true
    ln -s ${pkgs.maven}/bin $out/usr/share/maven/bin 2>/dev/null || true

    mkdir -p $out/usr/bin
    ln -s ${pkgs.maven}/bin/mvn $out/usr/bin/mvn
  '';

in
mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "maven";
  tag = "maven";
  toolchainPackages = [
    pkgs.jdk21
    pkgs.maven
  ];
  extraCopyToRoot = [ mavenInstall ];
  envVars = [
    "MAVEN_HOME=/usr/share/maven"
    "MAVEN_ARGS=-Dmaven.repo.local=/home/dependabot/.m2"
    "JAVA_HOME=${pkgs.jdk21}"
  ];
}
