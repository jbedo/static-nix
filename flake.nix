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
        packages =
          let
            TMPDIR = "/vast/scratch/users/bedo.j/slurm-test/tmp";
            STOREROOT = "/vast/scratch/users/bedo.j/slurm-test";
            SRUN = "/usr/bin/srun";
            SALLOC = "/usr/bin/salloc";

            patch = pkgs.runCommand "patch-patch.patch"
              { inherit STOREROOT SRUN SALLOC; } ''
              substitute ${./slurm-submit.patch} $out \
                --subst-var STOREROOT \
                --subst-var SRUN \
                --subst-var SALLOC \
            '';

            slurmNix = patchedNix.overrideAttrs (attrs: {
              patches = attrs.patches ++ [ patch ];
            });

            ssh-wrapper = pkgs.writeScript "ssh-wrapper" ''
              #!/bin/sh
              SCRIPT_DIR="$( cd -- "$( dirname -- "''${BASH_SOURCE[0]}" )" &> /dev/null && pwd -P)"
              LIBEXEC="$SCRIPT_DIR/../libexec/nix"
              exec $LIBEXEC/bash -c 'exec ./bin/$SSH_ORIGINAL_COMMAND'
            '';

            nix-wrapper = pkgs.writeScript "nix-wrapper" ''
              #!/bin/sh
              SCRIPT_DIR="$( cd -- "$( dirname -- "$0" )" &> /dev/null && pwd -P)"
              LIBEXEC="$SCRIPT_DIR/../libexec/nix"
              export TMPDIR=${TMPDIR}
              exec $LIBEXEC/nix-user-chroot ${STOREROOT}/nix $LIBEXEC/nix "$@"
            '';


            bundler = what:
              pkgs.runCommand "build-bundle" { } ''
                ${pkgs.haskellPackages.arx}/bin/arx tmpx --tmpdir "${STOREROOT}" ${slurm} // ./bin/${what} > $out
                chmod 755 $out
              '';

            slurm =
              pkgs.runCommand "slurm-nix.tar.bz2" { } ''
                install -Dm 755 ${nix-wrapper} out/bin/nix
                install -Dm 755 ${slurmNix}/bin/nix out/libexec/nix/nix
                install -Dm 755 ${pkgs.pkgsStatic.bash}/bin/bash out/libexec/nix/bash
                install -Dm 755 ${nix-user-chroot} out/libexec/nix/nix-user-chroot
                install -Dm 755 ${ssh-wrapper} out/bin/ssh-wrapper
                ln -s ../../bin/nix out/libexec/nix/build-remote
                
                for cmd in build channel collect-garbage copy-closure daemon env hash instantitate prefetch-url shell store ; do
                  ln -s ./nix out/bin/nix-$cmd
                done
                
                tar -Jcvf $out -C ./out .
              '';

          in
          {
            inherit slurm;
            slurm-ssh-wrapper-bundle = bundler "ssh-wrapper";
          };

        defaultPackage =
          pkgs.runCommand "build-package" { } ''
            install -D ${patchedNix}/bin/nix $out/bin/nix
            install -D ${pkgs.pkgsStatic.bash}/bin/bash $out/libexec/nix/bash
            ln -s ../../bin/nix $out/libexec/nix/build-remote
          '';
      });
}

