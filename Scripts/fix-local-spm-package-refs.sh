#!/usr/bin/env bash
# XcodeGen omits `package =` on XCSwiftPackageProductDependency for local packages
# (yonaskolb/XcodeGen#1549). Without it Xcode reports Missing package product for
# CleverAdsSolutionsSPM and often cascades to other SPM products.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBXPROJ="$ROOT/AltonApp.xcodeproj/project.pbxproj"

python3 - <<'PY' "$PBXPROJ"
import re, sys
path = sys.argv[1]
text = open(path).read()

# Find local package ref id for Vendor/CASBase
m = re.search(
    r'([A-F0-9]{24}) /\* XCLocalSwiftPackageReference "Vendor/CASBase" \*/',
    text,
)
if not m:
    print("fix-local-spm: no XCLocalSwiftPackageReference for Vendor/CASBase — skip")
    sys.exit(0)
pkg_id = m.group(1)
pkg_comment = f'{pkg_id} /* XCLocalSwiftPackageReference "Vendor/CASBase" */'

def patch_product(name: str, src: str) -> str:
    pattern = re.compile(
        rf'( /\* {re.escape(name)} \*/ = \{{\n'
        rf'\t\t\tisa = XCSwiftPackageProductDependency;\n)'
        rf'(\t\t\tpackage = [^\n]+;\n)?'
        rf'(\t\t\tproductName = {re.escape(name)};)',
    )
    def repl(match: re.Match) -> str:
        return f"{match.group(1)}\t\t\tpackage = {pkg_comment};\n{match.group(3)}"
    new, n = pattern.subn(repl, src, count=1)
    if n == 0:
        print(f"fix-local-spm: product {name} not found — skip")
        return src
    print(f"fix-local-spm: linked {name} → Vendor/CASBase")
    return new

updated = patch_product("CleverAdsSolutionsSPM", text)
if updated != text:
    open(path, "w").write(updated)
PY
