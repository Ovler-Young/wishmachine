{
  description = "DeepSeek Harness with Cloudflare Tunnel";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      runtime = import ./nix/runtime.nix { inherit pkgs; };
    in {
      packages.${system} = {
        inherit (runtime) dsh image;
        default = runtime.image;
      };
      checks.${system}.entrypoint = pkgs.runCommand "wishmachine-entrypoint-test" {
        nativeBuildInputs = [ pkgs.nodejs_24 pkgs.bash ];
      } ''
        cd ${self}
        node --test tests/entrypoint.test.mjs
        touch "$out"
      '';
      devShells.${system}.default = pkgs.mkShell {
        packages = [ (import ./nix/nodejs.nix { inherit pkgs; }) pkgs.pnpm_11 pkgs.jq ];
      };
    };
}
