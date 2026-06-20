# ilsh — the virtual filesystem

`ilsh` can present a small Unix-like directory tree over the real Windows filesystem.
It is **off by default**, so scripts written before this feature behave exactly as they
did (real Windows paths everywhere). Turn it on with a command-line flag or from your
startup script.

## Turning it on

```
ilsh --home C:\Users\me\project      # enable; /home points at that directory
```

or, inside the shell (e.g. from `.ilshellrc`):

```
vfs on                # enable; /home = the current real directory
vfs on C:\path        # enable; /home = C:\path
vfs off               # back to plain real-path mode
vfs status            # show the current layout
```

## The layout

| Virtual | Default real target | Notes |
|---|---|---|
| `/` | — (virtual) | `ls /` lists the mounts |
| `/home` | the `--home` directory | your working directory; the prompt starts here |
| `/home/windows` | `%USERPROFILE%` (e.g. `C:\Users\me`) | your real Windows home |
| `/bin` | `<repo>\out` | the compilers and utilities |
| `/etc` | `<repo>\etc` | config files |
| `/include` (or `/includes`) | `<repo>\include` | include files |
| `/lib` | `<repo>\out` | .NET libraries the compilers need |
| `/tmp` | `<repo>\tmp` | scratch space |

Each mount is just a **shell variable** holding a real Windows path (`home`, `bin`,
`etc`, `include`, `lib`, `tmp`, `windows`). Repoint any of them at any time — and several
virtual folders may point at the same real folder:

```
bin=C:\tools\bin
include=C:\myproject\include
etc=C:\myproject        # /etc and /home can share a real folder
```

## Reaching the real filesystem

When the VFS is on, ordinary commands (`cd`, `pwd`, `ls`, `cat`, `cp`, redirections, …)
work in virtual space. Three companions reach the **real** Windows filesystem directly:

```
lcd C:\Windows\System32     # change the real working directory
lpwd                        # print the real working directory
lls -al C:\Users\me         # list a real directory
```

## Startup script

An interactive shell runs `~/.ilshellrc` once at startup, from `/home`. Like any dotfile
it is hidden from `ls` unless you pass `ls -al`. It is the preferred place to configure
the shell — enable the VFS, repoint mounts, define aliases. If there is no `.ilshellrc`,
ilsh falls back to `~/.bashrc`. A template lives in `shell/dot-ilshellrc.sample`.

## Backward compatibility

With the VFS off (the default), `vmap()` is the identity function: every path passes
through untouched and the shell behaves exactly as before. The feature only changes
behavior once you opt in.
