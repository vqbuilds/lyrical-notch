#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p dist
COPYFILE_DISABLE=1 tar -czf dist/lyrical-notch-0.5.3-source.tar.gz \
  .gitignore .github Package.swift Package.resolved Sources build.sh \
  README.md LICENSE THIRD_PARTY_NOTICES.md CHANGELOG.md CONTRIBUTING.md docs \
  scripts/package-source.sh scripts/measure-cpu.py
print "Fuentes: $PWD/dist/lyrical-notch-0.5.3-source.tar.gz"
