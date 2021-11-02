{
  inputs.nix.url = "github:nixos/nix";
  inputs.nixpkgs.url = "nixpkgs/nixos-21.05-small";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nix, nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        patchedNix = nix.packages."${system}".nix-static.overrideAttrs (_: {
          patches = [ ./ca-cert-path.patch ./relocatable.patch ./cross-fingers.patch ./fixed-output.patch ];
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
            SLURMPREFIX = "/usr/bin/";
            useProot = true;

            SRUN = "${SLURMPREFIX}/srun";
            SALLOC = "${SLURMPREFIX}/salloc";

            patch = pkgs.runCommand "patch-patch.patch"
              { inherit STOREROOT SRUN SALLOC; } ''
              substitute ${./slurm-submit.patch} $out \
                --subst-var STOREROOT \
                --subst-var SRUN \
                --subst-var SALLOC \
            '';

            makeWrapper = name: script: pkgs.writeScript name ''
              #!/bin/sh
              SRC="$0"
              BASE=''${SRC##*/}
              DIR=''${SRC%"$BASE"}
              SCRIPT_DIR="$( cd -- "$DIR" &> /dev/null && pwd -P)"
              LIBEXEC="$SCRIPT_DIR/../libexec/nix"
              export TMPDIR=${TMPDIR}
              mkdir -p ${TMPDIR}
              mkdir -p ${STOREROOT}/nix
              ${script}
            '';

            slurmNix = patchedNix.overrideAttrs (attrs: {
              patches = attrs.patches ++ [ patch ];
            });

            ssh-wrapper = makeWrapper "ssh-wrapper" ''
              exec $LIBEXEC/nix-user-chroot "${STOREROOT}/nix" $LIBEXEC/bash -c 'exec ./bin/$SSH_ORIGINAL_COMMAND'
            '';

            nix-wrapper = makeWrapper "nix-wrapper" ''
              exec $LIBEXEC/nix-user-chroot "${STOREROOT}/nix" $SCRIPT_DIR/nix "$@"
            '';

            proot-wrapper = makeWrapper "proot-wrapper" ''
              ROOT="$1"
              shift
              exec $SCRIPT_DIR/proot -b "$ROOT":/nix/ "$@"
            '';

            proot = pkgs.fetchurl {
              url = "https://github.com/proot-me/proot/releases/download/v5.2.0/proot-v5.2.0-x86_64-static";
              sha256 = "sha256-6wZDs8SnfGsoe8Ev0WrXqUhs0vPE72Oh7oyn74pK4vA=";
            };

            bundler = what:
              pkgs.runCommand "build-bundle" { } ''
                  ${pkgs.haskellPackages.arx}/bin/arx tmpx --tmpdir "${STOREROOT}" ${tarball} // ./bin/${what} > $out
                chmod 755 $out
              '';

            tarball =
              pkgs.runCommand "slurm-nix.tar.bz2" { } ''
                install -Dm 755 ${slurmNix}/bin/nix out/bin/nix
                install -Dm 755 ${pkgs.pkgsStatic.bash}/bin/bash out/libexec/nix/bash
                install -Dm 755 ${ssh-wrapper} out/bin/ssh-wrapper
                install -Dm 755 ${nix-wrapper} out/bin/nix-wrapper
                ln -s ../../bin/nix out/libexec/nix/build-remote
                
                ${if useProot then ''
                  install -Dm 755 ${proot} out/libexec/nix/proot
                  install -Dm 755 ${proot-wrapper} out/libexec/nix/nix-user-chroot
                '' else ''
                  install -Dm 755 ${nix-user-chroot} out/libexec/nix/nix-user-chroot
                ''}
                
                
                for cmd in build channel collect-garbage copy-closure daemon env hash instantitate prefetch-url shell store ; do
                  ln -s ./nix out/bin/nix-$cmd
                done
                
                tar -Jcvf $out -C ./out .
              '';

          in
          {
            slurm = tarball;
            slurm-ssh-wrapper-bundle = bundler "ssh-wrapper";
            slurm-nix-wrapper-bundle = bundler "nix-wrapper";
          };

        defaultPackage =
          pkgs.runCommand "build-package" { } ''
            install -D ${patchedNix}/bin/nix $out/bin/nix
            install -D ${pkgs.pkgsStatic.bash}/bin/bash $out/libexec/nix/bash
            ln -s ../../bin/nix $out/libexec/nix/build-remote
          '';
      });
}


