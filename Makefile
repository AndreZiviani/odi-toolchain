# odi-toolchain -- the cross toolchains for the ODI DFP-34X-2C2 projects, as
# container images. README.md has what each image is for and how consumers
# pin them.
#
# Local builds are tagged :local. The published images are built by
# .github/workflows/ci.yml from a tag (uclibc-v*, freestanding-v*), never from
# a laptop.

FREESTANDING := odi-toolchain-freestanding:local
UCLIBC       := odi-toolchain-uclibc:local
JOBS         ?= 4

.PHONY: help freestanding uclibc test lint

help:
	@echo "make freestanding   build $(FREESTANDING) (about two minutes)"
	@echo "make uclibc         build $(UCLIBC) (about an hour; JOBS=$(JOBS))"
	@echo "make test           the ISA audit self-test, in the freestanding image"
	@echo "make lint           shellcheck every script"

freestanding:
	docker build -f freestanding/Dockerfile -t $(FREESTANDING) .

uclibc:
	docker build --build-arg JOBS=$(JOBS) -f uclibc/Dockerfile -t $(UCLIBC) .

test: freestanding
	docker run --rm -v "$(CURDIR)":/t -w /t $(FREESTANDING) sh test/run.sh

lint:
	shellcheck -S warning uclibc/*.sh common/*.sh test/*.sh
	shellcheck -S warning -s sh isa/isa-audit isa/isa-allowlist
	@# The rule the other ODI repos keep: no apostrophe in a shell comment,
	@# since one inside a single-quoted inline block ends the block.
	@if grep -nE "^[[:space:]]*#.*'" uclibc/*.sh common/*.sh test/*.sh isa/*; then \
		echo "lint: apostrophe in a shell comment above -- rephrase" >&2; exit 1; fi
	@echo "lint: clean"
