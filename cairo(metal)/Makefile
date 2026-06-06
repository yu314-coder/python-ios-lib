# ============================================================================
# CairoMetal — Makefile (clang/metal fallback build)
# ----------------------------------------------------------------------------
# Primary build path is Package.swift (`swift build`). This Makefile is the
# command-line fallback: it compiles the C / Objective-C sources with clang
# (ARC on for the .m files), compiles the Metal shader with `xcrun metal`, and
# links the `demo` smoke test.
#
# Targets
#   make            -> lib + metallib + demo            (default: all)
#   make lib        -> build/libcairometal.a            (static library)
#   make metallib   -> build/default.metallib           (compiled shaders)
#   make demo       -> build/demo                        (renders demo.png)
#   make run        -> build + run demo (writes build/demo.png)
#   make clean      -> remove build/
#
# Source / shader inventory (single source of truth for the CLI build; matches
# the files that actually exist on disk and Package.swift's `sources`):
#   C source     : src/cm_matrix.c
#   Obj-C sources: src/cairo_metal.m src/cm_surface.m src/cm_device.m
#                  src/cm_path.m src/cm_fill.m src/cm_stroke.m src/cm_paint.m
#   Shaders      : shaders/fill.metal -> default.metallib
#   Public header: include/cairo_metal.h   Internal: src/cm_internal.h
# ============================================================================

# ---- toolchain -------------------------------------------------------------
CC            := xcrun -sdk macosx clang
METAL         := xcrun -sdk macosx metal
METALLIB      := xcrun -sdk macosx metallib

# Default to the host arch; override on the command line, e.g.
#   make ARCH="-arch arm64"      make ARCH="-arch arm64 -arch x86_64"
ARCH          ?= -arch $(shell uname -m)

# ---- directories -----------------------------------------------------------
SRC_DIR       := src
SHADER_DIR    := shaders
EXAMPLE_DIR   := examples
INCLUDE_DIR   := include
BUILD_DIR     := build
OBJ_DIR       := $(BUILD_DIR)/obj

# ---- flags -----------------------------------------------------------------
WARN          := -Wall -Wextra -Wno-unused-parameter
OPT           ?= -O2
STD_C         := -std=c11
INCLUDES      := -I$(INCLUDE_DIR) -I$(SRC_DIR)
# -fmodules lets the .m files `@import`/auto-link the system frameworks cleanly.
CFLAGS        := $(ARCH) $(STD_C) $(OPT) $(WARN) $(INCLUDES) -fmodules
OBJCFLAGS     := $(ARCH) $(STD_C) $(OPT) $(WARN) $(INCLUDES) -fobjc-arc -fmodules

# Frameworks required by the library implementation (device/surface/encode +
# CoreText for cm_text.m and ImageIO/CoreGraphics/UniformTypeIdentifiers for
# cm_surface_png.m, which now live in the library, not just the demo).
LIB_FRAMEWORKS := -framework Metal \
                  -framework MetalKit \
                  -framework QuartzCore \
                  -framework CoreVideo \
                  -framework IOSurface \
                  -framework Foundation \
                  -framework CoreFoundation \
                  -framework CoreText \
                  -framework CoreGraphics \
                  -framework ImageIO \
                  -framework UniformTypeIdentifiers

# The demo links the same framework set as the library.
DEMO_FRAMEWORKS := $(LIB_FRAMEWORKS)

# ---- file lists ------------------------------------------------------------
C_SRCS := \
  $(SRC_DIR)/cm_matrix.c \
  $(SRC_DIR)/cm_surface_format.c \
  $(SRC_DIR)/cm_surface_similar.c \
  $(SRC_DIR)/cm_state.c \
  $(SRC_DIR)/cm_pattern.c \
  $(SRC_DIR)/cm_mesh.c \
  $(SRC_DIR)/cm_raster.c \
  $(SRC_DIR)/cm_query.c \
  $(SRC_DIR)/cm_region.c \
  $(SRC_DIR)/cm_font.c \
  $(SRC_DIR)/cm_ft.c

OBJC_SRCS := \
  $(SRC_DIR)/cairo_metal.m \
  $(SRC_DIR)/cm_surface.m \
  $(SRC_DIR)/cm_surface_png.m \
  $(SRC_DIR)/cm_recording.m \
  $(SRC_DIR)/cm_device.m \
  $(SRC_DIR)/cm_clip.m \
  $(SRC_DIR)/cm_group.m \
  $(SRC_DIR)/cm_compose.m \
  $(SRC_DIR)/cm_text.m \
  $(SRC_DIR)/cm_path.m \
  $(SRC_DIR)/cm_fill.m \
  $(SRC_DIR)/cm_stroke.m \
  $(SRC_DIR)/cm_paint.m

# fill.metal compiles into the single default.metallib; it defines every shader
# entry point the device module references (cm_vs_stencil / cm_fs_stencil /
# cm_vs_cover / cm_fs_cover_solid / cm_fs_cover_linear).
METAL_SRCS := \
  $(SHADER_DIR)/fill.metal

C_OBJS    := $(patsubst $(SRC_DIR)/%.c,$(OBJ_DIR)/%.o,$(C_SRCS))
OBJC_OBJS := $(patsubst $(SRC_DIR)/%.m,$(OBJ_DIR)/%.o,$(OBJC_SRCS))
ALL_OBJS  := $(C_OBJS) $(OBJC_OBJS)

METAL_AIRS := $(patsubst $(SHADER_DIR)/%.metal,$(BUILD_DIR)/%.air,$(METAL_SRCS))

LIB          := $(BUILD_DIR)/libcairometal.a
METALLIB_OUT := $(BUILD_DIR)/default.metallib
DEMO         := $(BUILD_DIR)/demo

# ============================================================================
# Phony targets
# ============================================================================
.PHONY: all lib metallib demo run clean print-sources

all: lib metallib demo

lib: $(LIB)

metallib: $(METALLIB_OUT)

demo: $(DEMO) $(METALLIB_OUT)

# Build then run the smoke test; demo writes build/demo.png next to the binary
# and locates build/default.metallib via $CM_METALLIB.
run: demo
	cd $(BUILD_DIR) && CM_METALLIB="$(abspath $(METALLIB_OUT))" ./demo demo.png

# Echo the full source + shader inventory (handy for CI / sanity).
print-sources:
	@echo "C sources:     $(C_SRCS)"
	@echo "Obj-C sources: $(OBJC_SRCS)"
	@echo "Shaders:       $(METAL_SRCS)"
	@echo "Public hdr:    $(INCLUDE_DIR)/cairo_metal.h"
	@echo "Internal hdr:  $(SRC_DIR)/cm_internal.h"

clean:
	rm -rf $(BUILD_DIR)

# ============================================================================
# Build rules
# ============================================================================

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# C modules.
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(INCLUDE_DIR)/cairo_metal.h $(SRC_DIR)/cm_internal.h | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@

# Objective-C modules (ARC).
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.m $(INCLUDE_DIR)/cairo_metal.h $(SRC_DIR)/cm_internal.h | $(OBJ_DIR)
	$(CC) $(OBJCFLAGS) -c $< -o $@

# Static library.
$(LIB): $(ALL_OBJS) | $(BUILD_DIR)
	libtool -static -o $@ $(ALL_OBJS)

# Metal shaders -> AIR -> single metallib (default.metallib).
# Each .metal compiles to its own .air; metallib links them together.
# NOTE: do NOT pass the host $(ARCH) (e.g. -arch arm64) to `metal` — the Metal
# frontend targets AIR, not a CPU arch, and a host -arch flag crashes it.
$(BUILD_DIR)/%.air: $(SHADER_DIR)/%.metal | $(BUILD_DIR)
	$(METAL) -c $< -o $@

$(METALLIB_OUT): $(METAL_AIRS)
	$(METALLIB) $(METAL_AIRS) -o $@

# Demo smoke test: links the static lib + frameworks, renders three shapes to a
# PNG. Built directly from examples/demo.m (compiled with ARC).
$(DEMO): $(EXAMPLE_DIR)/demo.m $(LIB) $(INCLUDE_DIR)/cairo_metal.h | $(BUILD_DIR)
	$(CC) $(OBJCFLAGS) $(EXAMPLE_DIR)/demo.m $(LIB) $(DEMO_FRAMEWORKS) -o $@
