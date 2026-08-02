# swsql - a PostgreSQL client for the terminal
#
# libpq is keg-only on Homebrew and lives outside the default pkg-config search
# path, so this Makefile finds it rather than making every contributor export
# PKG_CONFIG_PATH by hand. `swift build` works directly too, if the path is set.

SHELL := /bin/bash

# Candidate directories holding libpq.pc, in order of preference.
LIBPQ_PKGCONFIG := $(shell \
	for prefix in \
		"$$(brew --prefix libpq 2>/dev/null)" \
		"$$(brew --prefix postgresql@17 2>/dev/null)" \
		"$$(brew --prefix postgresql@16 2>/dev/null)" \
		"$$(pg_config --libdir 2>/dev/null)/.." ; do \
		if [ -n "$$prefix" ] && [ -f "$$prefix/lib/pkgconfig/libpq.pc" ]; then \
			echo "$$prefix/lib/pkgconfig"; break; \
		fi; \
	done)

export PKG_CONFIG_PATH := $(LIBPQ_PKGCONFIG):$(PKG_CONFIG_PATH)

PREFIX ?= /usr/local

.PHONY: all build release test run install clean check-libpq

all: build

check-libpq:
	@pkg-config --exists libpq || { \
		echo "error: libpq not found."; \
		echo "  macOS:  brew install libpq"; \
		echo "  Debian: apt install libpq-dev"; \
		echo "Then re-run make, or set PKG_CONFIG_PATH to the directory holding libpq.pc."; \
		exit 1; \
	}
	@echo "libpq $$(pkg-config --modversion libpq) from $(LIBPQ_PKGCONFIG)"

build: check-libpq
	swift build

release: check-libpq
	swift build -c release

test: check-libpq
	swift test

# Usage: make run ARGS="mydb"
run: build
	swift run swsql $(ARGS)

install: release
	install -d "$(PREFIX)/bin"
	install -m 0755 .build/release/swsql "$(PREFIX)/bin/swsql"
	@echo "installed $(PREFIX)/bin/swsql"

clean:
	swift package clean
