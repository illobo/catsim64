# Cat Simulator 64
#   make          catsim.prg (needs 64tass)
#   make gen      regenerate the .inc files (Python 3; PIL only for --preview;
#                 the C64 character ROM: VICE's, or CHARGEN=/path)
#   make release  release/catsim64-<VERSION>/: crunched PRG, D64, README.TXT,
#                 and a zip (needs exomizer and c1541)
#   make dist     dist/: the minimal source tree to publish
VERSION := $(shell cat VERSION)
REL     := release/catsim64-$(VERSION)
GEN     = catsim.inc catspr.inc catleft.inc title.inc

all: catsim.prg

catsim.prg: catsim.asm player.asm title.asm $(GEN) VERSION
	64tass -C -a catsim.asm -o $@ -l catsim.lbl

gen:
	python3 gen.py

release: catsim.prg README.TXT
	rm -rf $(REL) $(REL).zip
	mkdir -p $(REL)
	exomizer sfx sys -n -q -o $(REL)/catsim64.prg catsim.prg
	c1541 -format "cat simulator 64,64" d64 $(REL)/catsim64.d64 \
	  -write $(REL)/catsim64.prg catsim64 >/dev/null
	cp README.TXT $(REL)/
	cd release && zip -qr catsim64-$(VERSION).zip catsim64-$(VERSION)
	@ls -l $(REL) $(REL).zip

DIST_FILES = LICENSE Makefile README.md README.TXT VERSION .gitignore docs/index.html \
	catsim.asm player.asm title.asm $(GEN) gen.py title.py art/art.py art/art2.py
dist: release
	mkdir -p dist/art dist/docs/img dist/docs/download
	for f in $(DIST_FILES); do cp $$f dist/$$f; done
	cp docs/img/*.png dist/docs/img/
	mkdir -p dist/docs/fonts && cp docs/fonts/* dist/docs/fonts/
	cp $(REL)/catsim64.prg $(REL)/catsim64.d64 dist/docs/download/
	@echo "dist/ ready: $(DIST_FILES)"

clean:
	rm -f catsim.prg catsim.lbl

.PHONY: all gen release dist clean
