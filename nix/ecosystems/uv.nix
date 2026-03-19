# uv.nix: UV (Python) ecosystem image — core + Python versions + uv binary.
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
  name = "uv";
  tag = "uv";
  toolchainPackages = [
    pkgs.python311
    pkgs.python312
    pkgs.python313
    pkgs.python314
    pkgs.uv
  ];
  envVars = [
    "REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt"
    "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt"
  ];
}
