# gradle.nix: Gradle ecosystem image — core + JDK 21 + Gradle.
{
  pkgs,
  n2c,
  coreImage,
  mkEcosystemImage,
  src,
}:

mkEcosystemImage {
  inherit
    pkgs
    n2c
    coreImage
    src
    ;
  name = "gradle";
  tag = "gradle";
  toolchainPackages = [
    pkgs.jdk21
    pkgs.gradle
  ];
  envVars = [
    "JAVA_HOME=${pkgs.jdk21}"
  ];
}
