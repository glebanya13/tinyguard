#!/usr/bin/env bash
# Repository size report and history-cleanup PLAN (docs/REPO_SIZE.md). DRY RUN ONLY:
# this script never rewrites history, never deletes anything in the repository, never
# pushes and never runs `git gc`. It only reads, prints numbers and prints the commands
# the owner would run by hand. Its only writes are two small temp files, removed at exit.
#
# Usage: tools/slim_repo.sh [--top N] [--paths 'glob1 glob2 ...']
#   --top N     how many of the biggest blobs to list (default 20)
#   --dump-ids F  also write the blob ids to strip into file F (input of filter-repo)
#   --paths     pathspec globs whose OLD versions may be dropped from history
#               (default: assets/models/*.glb docs/screenshots/*.png assets/store/*.png)
# Needs: git, awk, sort. Optional for the real run later: git-filter-repo, git-lfs.
set -eu

TOP=20
DUMP=""
PATHS='assets/models/*.glb docs/screenshots/*.png assets/store/*.png'
while [ $# -gt 0 ]; do
	case "$1" in
		--top) TOP="${2:?--top needs a number}"; shift 2 ;;
		--dump-ids) DUMP="${2:?--dump-ids needs a file}"; shift 2 ;;
		--paths) PATHS="${2:?--paths needs globs}"; shift 2 ;;
		-h | --help) sed -n '2,13p' "$0"; exit 0 ;;
		*) echo "unknown argument: $1" >&2; exit 2 ;;
	esac
done

cd "$(dirname "$0")/.."
TMP="$(mktemp -d "${TMPDIR:-/tmp}/slim_repo.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

human() { awk -v b="$1" 'BEGIN { split("B KB MB GB", u); i = 1; while (b >= 1024 && i < 4) { b /= 1024; i++ } printf "%.1f %s", b, u[i] }'; }

echo "== 1. Repository now (git count-objects -vH)"
git count-objects -vH
echo "commits (all refs): $(git rev-list --count --all)"
echo

# All blobs in history: "<sha> <size> <path>" (one line per path name seen).
git rev-list --objects --all \
	| git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
	| awk '$1 == "blob" { print $2, $3, substr($0, index($0, $4)) }' > "$TMP/blobs.txt"

echo "== 2. Top $TOP blobs in history (size before git compression)"
sort -k2,2nr "$TMP/blobs.txt" | head -n "$TOP" | while read -r sha size path; do
	printf '%10s  %s  %s\n' "$(human "$size")" "${sha:0:10}" "$path"
done
echo

echo "== 3. History by extension (sum over all distinct blobs, before compression)"
awk '{ n = split($3, p, "."); e = (n > 1) ? tolower(p[n]) : "(none)"; s[e] += $2; c[e]++ }
	END { for (e in s) printf "%d %s %d\n", s[e], e, c[e] }' "$TMP/blobs.txt" \
	| sort -nr | head -n 12 | while read -r size ext count; do
		printf '%10s  .%-8s %5d blobs\n' "$(human "$size")" "$ext" "$count"
	done
echo

echo "== 4. What the cleanup would drop"
echo "paths: $PATHS"
# Blob ids that HEAD still uses: always kept.
git ls-tree -r HEAD | awk '{ print $3 }' | sort -u > "$TMP/head_blobs.txt"
# shellcheck disable=SC2086  # PATHS is a list of globs on purpose
git rev-list --objects --all -- $PATHS | awk 'NF > 1 { print $1 }' | sort -u > "$TMP/candidates.txt"
# Old versions = candidates that HEAD does not use.
comm -23 "$TMP/candidates.txt" "$TMP/head_blobs.txt" > "$TMP/strip_ids.txt"
awk 'NR == FNR { drop[$1] = 1; next } ($1 in drop) { size[$1] = $2 } END { for (s in size) { t += size[s]; n++ } printf "%d %d\n", t, n }' \
	"$TMP/strip_ids.txt" "$TMP/blobs.txt" > "$TMP/summary.txt"
read -r DROP_BYTES DROP_COUNT < "$TMP/summary.txt"
if [ -n "$DUMP" ]; then cp "$TMP/strip_ids.txt" "$DUMP"; echo "ids written to $DUMP"; fi
echo "old blob versions to strip: $DROP_COUNT, $(human "${DROP_BYTES:-0}") before compression"
echo "(current .git is above; objects in the pack are zlib-compressed, .glb/.png compress poorly,"
echo " so expect the packed saving to be close to this figure, not far below it.)"
echo

cat <<EOF
== 5. Plan (NOT executed; run by hand on a fresh mirror clone, with a backup)
 0. Agree with every collaborator: after step 4 everybody re-clones.
 1. git clone --mirror <origin> bimbleguard.mirror && cd bimbleguard.mirror
 2. List of blob ids to drop = section 4 (run: tools/slim_repo.sh --dump-ids strip_ids.txt):
      git filter-repo --strip-blobs-with-ids strip_ids.txt     # keeps the versions HEAD uses
    (alternative for whole paths: git filter-repo --path-glob 'assets/models/*.glb' --invert-paths,
     then re-add the current .glb in one commit.)
 3. Move binaries to Git LFS for the future (rewrites history again if done with
    'git lfs migrate import --include="*.glb,*.png,*.wav" --everything'; for new commits only,
    just add .gitattributes lines and 'git lfs track'):
      *.glb filter=lfs diff=lfs merge=lfs -text
      *.png filter=lfs diff=lfs merge=lfs -text
      *.wav filter=lfs diff=lfs merge=lfs -text
    CI and every clone then need git-lfs; check the hosting's LFS quota first.
 4. git reflog expire --expire=now --all && git gc --prune=now --aggressive
 5. git push --force --mirror <origin>      # only after the owner's explicit yes
 6. Compare: git count-objects -vH before/after (section 1), then everyone re-clones.
EOF
