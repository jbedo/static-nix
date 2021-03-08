This is a statically linked version of Nix with some patches intended
to ease the installation and usage of Nix on typical HPC clusters. The
binary is patched to:

1. Disable sqlite WAL: on networked systems with shared storage WAL does not
   work; disabling is an attempt to reduce possible corruption from invoking Nix
   on multiple nodes simultaniously.
2. Disable fallocate and luster xattr removal: Luster filesystems do not support
   fallocate and have unremovable extended attributes.
3. Expand CA certificate search path: CentOS among others store the CA bundle
   at a different location to the default fallback paths.
4. Make final binary relocatable: paths are searched relative to the Nix binary
   allowing the executable to be relocated anywhere.
5. Enable experimental features by default.

# Building

With Flakes enabled:

```
nix build github:jbedo/static-nix
```
