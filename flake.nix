{
  inputs.nix.url = "github:nixos/nix";
  inputs.nixpkgs.url = "nixpkgs/nixos-21.05-small";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nix, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        patchedNix = nix.packages."${system}".nix-static.overrideAttrs (_: {
          patches = [ ./ca-cert-path.patch ./relocatable.patch ];
          doCheck = false;
        });
        nix-user-chroot = pkgs.fetchurl {
          url = "https://github.com/nix-community/nix-user-chroot/releases/download/1.2.2/nix-user-chroot-bin-1.2.2-x86_64-unknown-linux-musl";
          sha256 = "sha256-4Rr/YEu40//R2cDGjNY2gW1+uNpUDeGO46QcytesCXI=";
        };
      in
      {
        packages.slurm =
          let slurmNix = patchedNix.overrideAttrs (attrs: {
            patches = attrs.patches ++ [ ./slurm-submit.patch ];
          }); in
          pkgs.runCommand "build-package" { } ''
            install -D ${slurmNix}/bin/nix $out/bin/nix
            install -D ${pkgs.pkgsStatic.bash}/bin/bash $out/libexec/nix/bash
            install -Dm 755 ${nix-user-chroot} $out/libexec/nix/nix-user-chroot
            ln -s ../../bin/nix $out/libexec/nix/build-remote
          '';
        defaultPackage =

          pkgs.runCommand "build-package" { } ''
            install -D ${patchedNix}/bin/nix $out/bin/nix
            install -D ${pkgs.pkgsStatic.bash}/bin/bash $out/libexec/nix/bash
            ln -s ../../bin/nix $out/libexec/nix/build-remote
          '';
      });
}

