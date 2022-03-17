This is a statically linked version of Nix with some patches intended to
ease the installation and usage of Nix on typical HPC clusters. There
are patches for:


1. Disable fallocate and luster xattr removal: Luster filesystems do not support
   fallocate and have unremovable extended attributes.
2. Expand CA certificate search path: CentOS among others store the CA bundle
   at a different location to the default fallback paths.
3. Make final binary relocatable: paths are searched relative to the Nix binary
   allowing the executable to be relocated anywhere.
4. Handle large file hash rewriting on disk rather than memory to allow large
   store objects. This currently relies on mmap and so only works on platforms
   supporting it.

# Building

With Flakes enabled:

```
nix build github:jbedo/static-nix
```

By default patches 2, 3, and 4 are enabled.

# Experimental SLURM submissions

There's a highly experimental patch, more of a POC, for adding SLURM
submission support to Nix.  This is intended to run on HPC systems
managed by SLURM queueing systems and submits _all_ builds as individual
jobs. This makes it easy to farm builds out across traditional HPC via a
remote store, with the nix-daemon running on a node with submission
permissions.


For this specific use case, the `slurm-ssh-wrapper-bundle` target
produces a single executable which can then be called via an ssh
authorized_keys entry like so:


```
command="/path/to/ssh-wrapper" ssh-rsa ...
```

The machine can then be used as a remote builder or store
(via `--builders` or `--store`) with the builds resulting
in slurm jobs.

The variables `TMPDIR`, `STOREROOT`, and `SLURMPREFIX` must be set
appropriately in flake.nix.

Resources to request for a derivation is specified via the `PPN`,
`MEMORY`, and `WALLTIME` attributes, e.g.,:


```
stdenv.mkDerivation {
  ...
  PPN = 10; # 10 CPUs
  MEMORY = "5G"; # 5 GiB of ram
  WALLTIME = "24:00:00"; # 1 day max walltime
}
```

## Use with BioNix

BioNix can be used with this experimental SLURM patch by passing the
resource requirements down through an overlay:

```
(_: super: {
  exec = f: x@{ ppn ? 1, mem ? 1, walltime ? "2:00:00", ... }: y:
    (f (removeAttrs x [ "ppn" "mem" "walltime" ]) y).overrideAttrs (attrs: {
      PPN = if attrs.passthru.multicore or false then ppn else 1;
      MEMORY = toString mem + "G";
      WALLTIME = walltime;
    });
})
```
