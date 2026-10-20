#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p dist
COPYFILE_DISABLE=1 tar -czf dist/notch-letras-0.5.2-source.tar.gz \
  .gitignore .github Package.swift Package.resolved Sources build.sh \
  README.md LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md CONTRIBUTING.md docs \
  scripts/package-source.sh scripts/measure-cpu.py
print "Fuentes: $PWD/dist/notch-letras-0.5.2-source.tar.gz"
