Tools that enable Zig to build things.

# How to Use

Build the `zig-toolchain` program with `zig build`.  Once built, you can run `zig-toolchain` to build one of the following toolchains:
```
# Generate an MSVC toolchain
zig-toolchain msvc

# TODO: more toolchains to come
```

These commands will build the toolchain in the `zig-cache` folder, either in the closest build directory (where `build.zig` lives) or it will fall back to your current directory.

Once the toolchain is generated, it may include additional instruction required to setup your shell environment.  For example:

```batch
> zig-toolchain msvc

Run the following to setup the environment in a BATCH shell:
D:\git\refterm\zig-cache\msvc-toolchain\bin\zig-env.bat
```
