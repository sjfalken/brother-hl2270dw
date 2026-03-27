{
  description = "Brother HL-2270DW CUPS driver";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "i686-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in {
          default = pkgs.callPackage ./default.nix {};
          brother-hl2270dw = pkgs.callPackage ./default.nix {};
        }
      );

      overlays.default = final: prev: {
        brother-hl2270dw = final.callPackage ./default.nix {};
      };
    };
}
