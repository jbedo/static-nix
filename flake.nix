{
  inputs.nix.url = "github:nixos/nix";
  inputs.nixpkgs.url = "nixpkgs/nixos-20.09-small";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nix, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: {
      defaultPackage = let
        pkgs = import nixpkgs { inherit system; };
        patchedNix = nix.packages."${system}".nix-static.overrideAttrs (_: {
          patches = [ ./experimental-features.patch ./relocatable.patch ./no-fallocate.patch ./lustre.patch ];
          doCheck = false;
        });
      in pkgs.runCommand "build-package" {} ''
        install -D ${patchedNix}/bin/nix $out/bin/nix
        install -D ${pkgs.pkgsStatic.bash}/bin/bash $out/libexec/nix/bash
        ln -s ../../bin/nix $out/libexec/nix/build-remote
      '';
    });
}
