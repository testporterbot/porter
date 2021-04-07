PKG = get.porter.sh/porter
SHELL = bash

# --no-print-directory avoids verbose logging when invoking targets that utilize sub-makes
MAKE_OPTS ?= --no-print-directory

COMMIT ?= $(shell git rev-parse --short HEAD)
VERSION ?= $(shell git describe --tags --match v* 2> /dev/null || echo v0)
PERMALINK ?= $(shell git describe --tags --exact-match --match v* &> /dev/null && echo latest || echo canary)

LDFLAGS = -w -X $(PKG)/pkg.Version=$(VERSION) -X $(PKG)/pkg.Commit=$(COMMIT)
GO = GO111MODULE=on go
# I am using both ways to disable http/2 which is causing us massive instability.  Hopefully one of them sticks.
XBUILD = CGO_ENABLED=0 GO111MODULE=on GODEBUG=http2client=0 $(GO) build -ldflags '$(LDFLAGS)' -tags nethttpomithttp2
BINDIR ?= bin/mixins/$(MIXIN)

CLIENT_PLATFORM ?= $(shell go env GOOS)
CLIENT_ARCH ?= $(shell go env GOARCH)
RUNTIME_PLATFORM ?= linux
RUNTIME_ARCH ?= amd64
# NOTE: When we add more to the build matrix, update the regex for porter mixins feed generate
SUPPORTED_PLATFORMS = linux darwin windows
SUPPORTED_ARCHES = amd64

ifeq ($(CLIENT_PLATFORM),windows)
FILE_EXT=.exe
else ifeq ($(RUNTIME_PLATFORM),windows)
FILE_EXT=.exe
else
FILE_EXT=
endif

.PHONY: build
build: build-client build-runtime

build-runtime:
	mkdir -p $(BINDIR)/runtimes
	GOARCH=$(RUNTIME_ARCH) GOOS=$(RUNTIME_PLATFORM) $(XBUILD) -o $(BINDIR)/runtimes/$(MIXIN)-runtime$(FILE_EXT) ./cmd/$(MIXIN)

build-client:
	mkdir -p $(BINDIR)
	GODEBUG=http2client=0 $(GO) build -ldflags '$(LDFLAGS)' -tags nethttpomithttp2 -o $(BINDIR)/$(MIXIN)$(FILE_EXT) ./cmd/$(MIXIN)

xbuild-all:
	$(foreach OS, $(SUPPORTED_PLATFORMS), \
		$(foreach ARCH, $(SUPPORTED_ARCHES), \
				$(MAKE) $(MAKE_OPTS) CLIENT_PLATFORM=$(OS) CLIENT_ARCH=$(ARCH) MIXIN=$(MIXIN) xbuild -f mixin.mk; \
		))
	@# Copy most recent build into bin/dev so that subsequent build steps can easily find it, not used for publishing
	rm -fr $(BINDIR)/dev
	cp -R $(BINDIR)/$(VERSION) $(BINDIR)/dev
	mage PrepareMixinForPublish $(MIXIN) $(VERSION) $(PERMALINK)

xbuild: $(BINDIR)/$(VERSION)/$(MIXIN)-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT)
$(BINDIR)/$(VERSION)/$(MIXIN)-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT):
	mkdir -p $(dir $@)
	GOOS=$(CLIENT_PLATFORM) GOARCH=$(CLIENT_ARCH) $(XBUILD) -o $@ ./cmd/$(MIXIN)

clean:
	-rm -fr bin/mixins/$(MIXIN)
