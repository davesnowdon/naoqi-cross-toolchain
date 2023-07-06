# DO NOT USE

# THIS IS A WORK IN PROGRESS

# naoqi-cross-toolchain
A cross-compilation toolchain that targets NAOqi with a modern toolset

## Get the settings used to build the Aldebaran toolchain

In the root of the Aldebaran cross toolchain, run the following:

```bash
cross/bin/i686-aldebaran-linux-gnu-ct-ng.config > aldebaran-toolchain.config
```

The file `aldebaran-toolchain.config` in this repo is the result of doing so.

## Building glibc 2.13

glibc 2.13 used by the Aldebaran toolchain is very old and does not know about recent versions of GNU make and gcc. You will need to tweak its configure script in order to get it to build.

In `config/.build/src/glibc-2.13/configure` change the following:


Line 5044 (gcc version):

```bash
    3.4* | 4.[0-9]* )
```bash

to

```bash
    3.4* | 4.[0-9]* | [789].* | 10.* | 11.* )
```bash


Line 5107 (make version):

```bash
    3.79* | 3.[89]*)
```

to

```bash
    3.79* | 3.[89]* | 4*)
```

```bash
diff -Naur configure.orig configure > configure.patch

```