# Makefile for Anteater

.PHONY: all build clean test

GO ?= go
GO_DOWNLOAD_RETRIES ?= 3

LDFLAGS := -s -w

all: build

# Download modules with retries to mitigate transient proxy/network EOF errors.
mod-download:
	@attempt=1; \
	while [ $$attempt -le $(GO_DOWNLOAD_RETRIES) ]; do \
		echo "Downloading Go modules ($$attempt/$(GO_DOWNLOAD_RETRIES))..."; \
		if $(GO) mod download; then \
			exit 0; \
		fi; \
		sleep $$((attempt * 2)); \
		attempt=$$((attempt + 1)); \
	done; \
	echo "Go module download failed after $(GO_DOWNLOAD_RETRIES) attempts"; \
	exit 1

# Build all Go packages currently in the tree.
build: mod-download
	@echo "Building Go packages..."
	$(GO) build -ldflags="$(LDFLAGS)" ./...

test:
	$(GO) test ./...

clean:
	$(GO) clean ./...
