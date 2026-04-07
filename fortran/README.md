# Fortran for iOS

## Approach: flang cross-compilation

Use LLVM flang to cross-compile Fortran → iOS arm64 object files.

### Install flang
```bash
brew install flang
```

### Cross-compile Fortran for iOS arm64
```bash
# flang compiles to LLVM IR, then llc targets iOS arm64
flang-new -target arm64-apple-ios17.0 -c lapack_routine.f90 -o lapack_routine.o

# Or use the iOS SDK:
flang-new -target arm64-apple-ios17.0 \
  -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
  -c source.f90 -o source.o
```

### Build scipy with flang for iOS
```bash
export FC="flang-new"
export FFLAGS="-target arm64-apple-ios17.0 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)"

# Use cibuildwheel with flang as Fortran compiler
CIBW_BUILD="cp314-ios_arm64_iphoneos" \
CIBW_XBUILD_TOOLS="meson ninja cmake flang-new" \
CIBW_ENVIRONMENT_IOS="FC=flang-new" \
python3.14 -m cibuildwheel --platform ios --output-dir ./wheels scipy/
```

## Status
- [x] flang available via homebrew
- [ ] scipy iOS build with flang
- [ ] scikit-learn iOS build (depends on scipy)
