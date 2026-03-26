# Pre-built fireactions v2.x binary from GitHub releases.
# Using the pre-built release avoids the Go 1.25 toolchain requirement.
{ lib, stdenv, fetchurl }:

stdenv.mkDerivation rec {
  pname = "fireactions";
  version = "2.0.3";

  src = fetchurl {
    url = "https://github.com/hostinger/fireactions/releases/download/v${version}/fireactions-v${version}-linux-amd64.tar.gz";
    # Run: nix-prefetch-url --type sha256 --unpack <url>
    sha256 = "16qz2ah1vq6vdqk9p1i9b3m77hiv7kjc4v1bw40qzysn4x07a4nn";
  };

  sourceRoot = ".";

  installPhase = ''
    mkdir -p $out/bin
    cp fireactions $out/bin/fireactions
    chmod +x $out/bin/fireactions
  '';

  meta = with lib; {
    description = "Self-hosted GitHub Actions runners using Firecracker microVMs";
    homepage = "https://github.com/hostinger/fireactions";
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "fireactions";
  };
}
