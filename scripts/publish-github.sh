#!/usr/bin/env bash
# publish-github.sh -- create a public GitHub repo and push this folder.
# Usage: ./publish-github.sh [--name NAME] [--private] [--org ORG]
set -euo pipefail
NAME="debian-vnc-vm"
VISIBILITY="public"
ORG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    --private) VISIBILITY="private" ;;
    --org) ORG="$2"; shift 2 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) echo "unknown: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v git >/dev/null || { echo "git required" >&2; exit 1; }
command -v curl >/dev/null || { echo "curl required" >&2; exit 1; }
[ -n "${GITHUB_TOKEN:-}" ] || { echo "set GITHUB_TOKEN (a GitHub PAT with repo scope) first" >&2; exit 1; }

# Who am I
API="https://api.github.com"
AUTH="Authorization: Bearer $GITHUB_TOKEN"
OWNER=$(curl -sS -H "$AUTH" "$API/user" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("login",""))')
[ -n "$OWNER" ] || { echo "could not resolve GitHub user from token" >&2; exit 1; }
if [ -n "$ORG" ]; then OWNER="$ORG"; fi

echo "GitHub user: $OWNER"
echo "Creating repo $OWNER/$NAME ($VISIBILITY)..."
curl -sS -X POST -H "$AUTH" -H "Accept: application/vnd.github+json" \
  "$API/user/repos" \
  -d "{\"name\":\"$NAME\",\"private\":$( [ "$VISIBILITY" = "private" ] && echo true || echo false ),\"description\":\"Portable QEMU/KVM Debian 12 VNC toolkit (host+guest scripts for Linux hosts and Windows 10 clients)\"}" \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("full_name") or d.get("message"))'

if [ ! -d .git ]; then git init -q; fi
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-kamil}" -c user.email="${GIT_AUTHOR_EMAIL:-kamil@z440}" \
  commit -m "Initial toolkit: portable QEMU/KVM Debian 12 VNC VM" >/dev/null 2>&1 || true
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git remote remove origin 2>/dev/null || true
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/$OWNER/$NAME.git"
git push -u origin "$BRANCH"
echo "Done: https://github.com/$OWNER/$NAME"
