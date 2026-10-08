#!/usr/bin/env bash
# baseline-audit.sh — repo-wide constitution guard
# (fw-gsd specs/004-fedora-version-alignment, T017).
#
# Caller repos pin a Fedora baseline; the audit hard-fails on:
#   1. any `^FROM` in a Containerfile* file not pinned to a sha256 digest
#      (`scratch` is exempt);
#   2. stale Fedora references below the baseline — `fedora[:space-]N`,
#      `Fedora N`, or the token `F<N>` with N below the baseline value;
#   3. hardening violations — untrusted base-image references (docker-library
#      node alpine images, docker-library golang images, docker.io registry-1
#      library mirror paths).
#
# A finding is waived when its line carries the marker:
#   # baseline-audit-ignore
#
# Usage: BASELINE=46 [SKIP_DIR=./path] ./.github/scripts/baseline-audit.sh [root]
#   BASELINE   Fedora baseline release; references below it fail (default: 46)
#   SKIP_DIR   optional extra directory to prune from the scan (the reusable
#              workflow uses this for its own tooling checkout at .fw-cicd)
#   [root]     directory to audit (default: current directory)
#
# Invoked by the reusable workflow .github/workflows/baseline-audit.yml; also
# usable locally ("bash .github/scripts/baseline-audit.sh" from a repo root)
# and testable standalone (bash -n validation runs in PR CI).

set -euo pipefail

BASELINE="${BASELINE:-46}"
ROOT="${1:-.}"
SELF="./.github/scripts/baseline-audit.sh"
SELF_LEGACY="./.github/workflows/baseline-audit.yml"

failures=0
INCLUDES=(--include='Containerfile*' --include='*.yml' --include='*.yaml' --include='*.md')
EXCLUDES=(--exclude-dir=.git --exclude-dir=node_modules)
PRUNE=(\( -path ./.git -o -path ./node_modules \))
if [ -n "${SKIP_DIR:-}" ]; then
  EXCLUDES+=(--exclude-dir="${SKIP_DIR#./}")
  PRUNE+=(-o -path "./${SKIP_DIR#./}")
fi

cd "${ROOT}"

# --- Check 1: every ^FROM in Containerfile* must be digest-pinned ----------
echo "::group::Check 1 — digest pins (Containerfile*)"
while IFS= read -r f; do
  while IFS= read -r line; do
    case "${line}" in *baseline-audit-ignore*) continue ;; esac
    image="${line#FROM }"; image="${image%% *}"
    case "${image}" in
      *@sha256:*|scratch) ;;
      *)
        echo "::error file=${f#./}::check 1 — FROM line is not digest-pinned: ${line}"
        failures=$((failures+1)) ;;
    esac
  done < <(grep '^FROM ' "${f}" || true)
done < <(find . "${PRUNE[@]}" -prune -o \
           -name 'Containerfile*' -print | sort)
echo "::endgroup::"

# --- Check 2: stale Fedora references below the baseline -------------------
echo "::group::Check 2 — stale Fedora references (below F${BASELINE})"
while IFS= read -r hit; do
  [ -n "${hit}" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"
  lineno="${rest%%:*}"; line="${rest#*:}"
  [ "${file}" = "${SELF}" ] && continue
  [ "${file}" = "${SELF_LEGACY}" ] && continue
  case "${line}" in *baseline-audit-ignore*) continue ;; esac
  n="$(printf '%s\n' "${line}" \
       | grep -oE '([Ff]edora[ :\-][0-9]+|\bF[0-9]+\b)' \
       | grep -oE '[0-9]+' | sort -n | head -n1)"
  if [ -n "${n}" ] && [ "${n}" -lt "${BASELINE}" ]; then
    echo "::error file=${file#./},line=${lineno}::check 2 — Fedora reference F${n} is below baseline F${BASELINE}: ${line}"
    failures=$((failures+1))
  fi
done < <(grep -RInE "${INCLUDES[@]}" "${EXCLUDES[@]}" \
           -e '([Ff]edora[ :\-][0-9]+|\bF[0-9]+\b)' . || true)
echo "::endgroup::"

# --- Check 3: hardening violations (untrusted base references) -------------
echo "::group::Check 3 — hardening violations (untrusted base references)"
while IFS= read -r hit; do
  [ -n "${hit}" ] || continue
  file="${hit%%:*}"; rest="${hit#*:}"
  lineno="${rest%%:*}"; line="${rest#*:}"
  [ "${file}" = "${SELF}" ] && continue
  [ "${file}" = "${SELF_LEGACY}" ] && continue
  case "${line}" in *baseline-audit-ignore*) continue ;; esac
  echo "::error file=${file#./},line=${lineno}::check 3 — untrusted base-image reference: ${line}"
  failures=$((failures+1))
done < <(grep -RInE "${INCLUDES[@]}" "${EXCLUDES[@]}" \
           -e 'node:[0-9]+-alpine' \
           -e '/golang:[0-9]' \
           -e 'registry-1\.docker\.io/library' . || true)
echo "::endgroup::"

echo
if [ "${failures}" -gt 0 ]; then
  echo "Baseline audit FAILED with ${failures} finding(s) (baseline F${BASELINE})."
  exit 1
fi
echo "Baseline audit passed (baseline F${BASELINE})."
