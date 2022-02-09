{
  inputs.nix.url = "github:nixos/nix";
  inputs.nixpkgs.url = "nixpkgs/nixos-21.05-small";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.arxsrc = {
    url = "github:solidsnack/arx";
    flake = false;
  };
  outputs = { self, nix, nixpkgs, flake-utils, arxsrc, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        patchedNix = nix.packages."${system}".nix-static.overrideAttrs (_: {
          patches = [ ./ca-cert-path.patch ./relocatable.patch ./cross-fingers.patch ./fixed-output.patch ];
          doCheck = false;
        });
      in
      {
        packages =
          let
            # Location of srun & sallocate binaries on the HPC system
            SLURMPREFIX = "/usr/bin/";

            # Location of nix store
            # Must be shared with build nodes
            STOREROOT = "/stornext/HPCScratch/$USER";

            # Location of temporary files (e.g., build directories)
            # Must be shared with build nodes
            TMPDIR = "${STOREROOT}/tmp";

            # Use proot instead of bubblewrap
            useProot = false;

            SRUN = "${SLURMPREFIX}/srun";
            SALLOC = "${SLURMPREFIX}/salloc";

            makeWrapper = name: minimal: script: pkgs.writeScript name ''
              #!/bin/sh
              set -e
              set -o pipefail

              function dirof {
                SRC="$1"
                BASE=''${SRC##*/}
                DIR=''${SRC%"$BASE"}
              }
              dirof "$0"
              SCRIPT_DIR="$( cd -- "$DIR" &> /dev/null && pwd -P)"
              ${pkgs.lib.optionalString (!minimal) ''
                dirof "$SCRIPT_DIR"
                LIBEXEC="''${DIR}libexec/nix"
                export TMPDIR="${TMPDIR}"
                export NIX_STOREROOT="${STOREROOT}"
                export NIX_SRUN="${SRUN}"
                export NIX_SALLOC="${SALLOC}"
                command -v mkdir &> /dev/null && mkdir -p "$TMPDIR"
                command -v mkdir &> /dev/null && mkdir -p "$NIX_STOREROOT"/nix
              ''}

              ${script}
            '';

            slurmNix = patchedNix.overrideAttrs (attrs: {
              patches = attrs.patches ++ [ ./slurm-submit.patch ];
            });

            arx' = pkgs.haskellPackages.arx.overrideAttrs
              (_: {
                version = "git";
                src = arxsrc;
                preConfigure = ''
                  echo "git" > version
                '';
                patches = [ ./arx-cwd.patch ];
              });

            chroot-wrapper = makeWrapper "chroot-wrapper" false ''
              exec $LIBEXEC/nix-user-chroot "$NIX_STOREROOT/nix" "$@"
            '';

            ssh-wrapper = makeWrapper "ssh-wrapper" false ''
              exec $LIBEXEC/nix-user-chroot "$NIX_STOREROOT/nix" $LIBEXEC/bash -c 'exec '"$SCRIPT_DIR"'/$SSH_ORIGINAL_COMMAND'
            '';

            nix-wrapper = makeWrapper "nix-wrapper" false ''
              exec $LIBEXEC/nix-user-chroot "$NIX_STOREROOT/nix" $SCRIPT_DIR/nix \
                --experimental-features 'nix-command flakes' \
                --option sandbox false "$@"
            '';

            proot-wrapper = makeWrapper "proot-wrapper" true ''
              ROOT="$1"
              shift
              exec $SCRIPT_DIR/proot -b "$ROOT":/nix/ "$@"
            '';

            bwrap-wrapper = makeWrapper "bwrap-wrapper" true ''
              ROOT="$1"
              shift
              rootArgs=""
              for path in /* ; do
                if [ "$path" != "/nix" ] && [ "$path" != "/dev" ] ; then
                  rootArgs="$rootArgs --bind $path $path"
                fi
              done
              exec $SCRIPT_DIR/bwrap --bind "$ROOT" /nix/ $rootArgs --dev-bind /dev /dev "$@"
            '';

            proot = pkgs.fetchurl {
              url = "https://github.com/proot-me/proot/releases/download/v5.2.0/proot-v5.2.0-x86_64-static";
              sha256 = "sha256-6wZDs8SnfGsoe8Ev0WrXqUhs0vPE72Oh7oyn74pK4vA=";
            };

            bundler = what:
              pkgs.runCommand "build-bundle" { } ''
                ${arx'}/bin/arx tmpx --tmpdir '${TMPDIR}' ${tarball} // ${what} > $out
                chmod 755 $out
              '';

            tarball =
              pkgs.runCommand "slurm-nix.tar.bz2" { } ''
                install -Dm 755 ${slurmNix}/bin/nix out/bin/nix
                install -Dm 755 ${pkgs.pkgsStatic.bash}/bin/bash out/libexec/nix/bash
                install -Dm 755 ${ssh-wrapper} out/bin/ssh-wrapper
                install -Dm 755 ${nix-wrapper} out/bin/nix-wrapper
                install -Dm 755 ${chroot-wrapper} out/bin/chroot-wrapper
                ln -s ../../bin/nix out/libexec/nix/build-remote

                ${if useProot then ''
                  install -Dm 755 ${proot} out/libexec/nix/proot
                  install -Dm 755 ${proot-wrapper} out/libexec/nix/nix-user-chroot
                '' else ''
                  install -Dm 755 ${pkgs.pkgsStatic.bubblewrap}/bin/bwrap out/libexec/nix/bwrap
                  install -Dm 755 ${bwrap-wrapper} out/libexec/nix/nix-user-chroot
                ''}


                for cmd in build channel collect-garbage copy-closure daemon env hash instantiate prefetch-url shell store ; do
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
