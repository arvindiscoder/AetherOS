#!/usr/bin/env bash
# Static checks that do not need root or a Debian build host.
#
#   bash tests/lint.sh
#
# This is intentionally conservative: it catches syntax errors, invalid JSON,
# malformed XML, missing executables, stale package names, and accidental
# references to removed helpers. It does not boot the image.
set -Eeuo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"
FAIL=0
note() { printf '  %s\n' "$*"; }
ok()   { printf 'ok   %s\n' "$*"; }
bad()  { printf 'FAIL %s\n' "$*" >&2; FAIL=1; }

echo "== shell syntax =="
while IFS= read -r -d '' f; do
  if bash -n "$f"; then
    ok "bash -n ${f#./}"
  else
    bad "bash -n ${f#./}"
  fi
done < <(find . -type f -name '*.sh' -print0 | sort -z)

# POSIX scripts are the overlay helpers. Validate with sh -n when available.
if command -v sh >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    if sh -n "$f"; then
      ok "sh -n ${f#./}"
    else
      bad "sh -n ${f#./}"
    fi
  done < <(find overlay -type f -perm -u+x -print0 | sort -z)
fi

# build.sh and installer are bash but have no .sh suffix.
bash -n build.sh && ok "bash -n build.sh" || bad "bash -n build.sh"
bash -n installer/aether-install && ok "bash -n installer/aether-install" || bad "bash -n installer/aether-install"

echo "== executable bits =="
for f in build.sh installer/aether-install scripts/*.sh \
         overlay/usr/local/bin/aether-* overlay/usr/local/sbin/aether-* \
         overlay/usr/local/lib/aether/packs/*; do
  [[ -f "$f" ]] || continue
  if [[ -x "$f" ]]; then ok "executable ${f#./}"; else bad "not executable: ${f#./}"; fi
done

echo "== JSON =="
if command -v python3 >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    if python3 -m json.tool "$f" >/dev/null 2>&1; then
      ok "json ${f#./}"
    else
      bad "json ${f#./}"
    fi
  done < <(find config overlay -type f -name '*.json' -print0 | sort -z)
else
  note "python3 unavailable; JSON checks skipped"
fi

echo "== XML =="
if command -v xmllint >/dev/null 2>&1; then
  while IFS= read -r -d '' f; do
    if xmllint --noout "$f" 2>/dev/null; then
      ok "xml ${f#./}"
    else
      bad "xml ${f#./}"
    fi
  done < <(find config overlay -type f \( -name '*.xml' -o -name '*.svg' \) -print0 | sort -z)
else
  note "xmllint unavailable; XML checks skipped (install libxml2-utils)"
fi

echo "== package list =="
CORE=config/packages.core
if grep -qE '^[[:space:]]*zram-generator[[:space:]]*$' "$CORE"; then
  bad "stale package zram-generator (use systemd-zram-generator)"
else
  ok "zram package name"
fi
if grep -qE '^[[:space:]]*sgdisk[[:space:]]*$' "$CORE"; then
  bad "sgdisk is a command from gdisk, not a package"
else
  ok "no sgdisk pseudo-package"
fi
if grep -qE '^[[:space:]]*python3-gbinder[[:space:]]*$' "$CORE" 2>/dev/null ||
   grep -qE 'apt-get[[:space:]].*python3-gbinder' overlay/usr/local/bin/aether-pack 2>/dev/null; then
  bad "stale python3-gbinder package"
else
  ok "no forced python3-gbinder"
fi

# Duplicate package names are harmless to apt but usually mean an editing error.
DUPS=$(grep -vE '^[[:space:]]*(#|$)' "$CORE" | sort | uniq -d)
if [[ -n "$DUPS" ]]; then bad "duplicate packages: $DUPS"; else ok "no duplicate core packages"; fi

echo "== DMG file-manager integration =="
if [[ -x overlay/usr/local/bin/aether-dmg ]] &&
   grep -Fqx '7zip' "$CORE" &&
   grep -Fqx 'dmg2img' "$CORE" &&
   grep -Fq '<mime-type type="application/x-apple-diskimage">' config/compat/mime/aether-compat.xml &&
   grep -Fq '<glob pattern="*.dmg"/>' config/compat/mime/aether-compat.xml &&
   grep -Fqx 'Exec=aether-dmg %f' overlay/usr/share/applications/aether-dmg.desktop &&
   grep -Fqx 'MimeType=application/x-apple-diskimage;' overlay/usr/share/applications/aether-dmg.desktop &&
   grep -Fqx 'application/x-apple-diskimage=aether-dmg.desktop' overlay/etc/xdg/mimeapps.list &&
   grep -Fqx 'application/x-apple-diskimage=aether-dmg.desktop;' overlay/etc/xdg/mimeapps.list &&
   grep -Fq 'aether-dmg.desktop' scripts/40-compat.sh; then
  ok "DMG extractor is installed, associated, and available to the file manager"
else
  bad "incomplete DMG extractor package, MIME, or desktop registration"
fi

echo "== required files =="
for f in VERSION build.sh scripts/00-host-check.sh scripts/10-fetch-base.sh \
         scripts/20-configure.sh scripts/30-desktop.sh scripts/40-compat.sh \
         scripts/50-kernel.sh scripts/60-squashfs.sh scripts/70-iso.sh \
         config/boot/grub.cfg config/kernel/aetheros.fragment \
         config/packages.core installer/aether-install \
         overlay/usr/local/bin/aether-browser \
         config/desktop/chromium/aether-astra/manifest.json; do
  [[ -f "$f" ]] && ok "present ${f}" || bad "missing ${f}"
done

echo "== version consistency =="
if [[ -f VERSION ]]; then
  V=$(tr -d '[:space:]' <VERSION)
  if grep -q "AetherOS $V" README.md docs/*.md 2>/dev/null; then
    ok "version $V used in documentation"
  else
    note "version $V not found in README/docs (not fatal)"
  fi
fi

echo "== shellcheck (optional) =="
if command -v shellcheck >/dev/null 2>&1; then
  # Only errors fail the lint; warnings are useful but noisy across Debian's
  # package versions and shell dialect differences.
  if find . -type f \( -name '*.sh' -o -name 'aether-*' \) -print0 |
      xargs -0 shellcheck -S error -x >/tmp/aether-shellcheck.log 2>&1; then
    ok "shellcheck (errors only)"
  else
    cat /tmp/aether-shellcheck.log >&2
    bad "shellcheck errors"
  fi
else
  note "shellcheck unavailable; install it for stricter checks"
fi

echo
if (( FAIL )); then
  echo "lint failed" >&2
  exit 1
fi
echo "lint passed"
