{ pkgs }:
# Harness' native loader reads Node internals and requires the official binary layout.
let
  release = builtins.fromJSON (builtins.readFile ./nodejs.json);
in
pkgs.stdenv.mkDerivation {
  pname = "nodejs-official";
  inherit (release) version;
  src = pkgs.fetchurl {
    url = "https://nodejs.org/dist/v${release.version}/node-v${release.version}-linux-x64.tar.xz";
    inherit (release) sha256;
  };
  nativeBuildInputs = [ pkgs.autoPatchelfHook ];
  buildInputs = [ pkgs.stdenv.cc.cc.lib ];
  dontStrip = true;
  # Preserve the official binary's ELF header order so Node can start after patching.
  patchelfFlags = [ "--no-sort" ];
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r bin include lib share "$out/"
    PATH="$out/bin:$PATH" patchShebangs --build "$out/lib/node_modules"
    runHook postInstall
  '';
  passthru.python = pkgs.python3;
}
