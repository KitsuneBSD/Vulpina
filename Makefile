# Vulpina — build wrapper around Swift Package Manager.
#
# Targets:
#   make          build in debug configuration (default)
#   make build    same as above
#   make release  build in release configuration
#   make test     build and run the test suite
#   make clean    remove build artifacts

SWIFT ?= swift
CONFIGURATION ?= debug
SWIFT_FLAGS ?=

BUILD_FLAGS = $(SWIFT_FLAGS)

.PHONY: all build release test clean

all: build

build:
	$(SWIFT) build $(BUILD_FLAGS)

release:
	$(SWIFT) build -c release $(SWIFT_FLAGS)

test:
	$(SWIFT) test $(SWIFT_FLAGS)

clean:
	$(SWIFT) package clean
