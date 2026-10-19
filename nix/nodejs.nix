{ pkgs }:
# Harness' native loader reads Node internals and requires the official binary layout.
pkgs.stdenv.mkDerivation {
  pname = "nodejs-official";
  version = "24.16.0";
  src = pkgs.fetchurl {
    url = "https://nodejs.org/dist/v24.16.0/node-v24.16.0-linux-x64.tar.xz";
    sha256 = "d804845d34eddc21dc1092b519d643ef40b1f58ec5dec5c22b1f4bd8fabde6c9";
  };
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];
  dontStrip = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r bin include lib share "$out/"
    runHook postInstall
  '';
  passthru.python = pkgs.python3;
}
