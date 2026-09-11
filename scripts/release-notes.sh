#!/usr/bin/env bash
# CHANGELOG から指定バージョンの節を抜き出し、リリース本文（中英併記）を組み立てる。
# 使い方: scripts/release-notes.sh 0.1.1 [> notes.md]
#
# GitHub の自動生成ノート（コミット一覧）ではなく、この本文をリリースに載せる。
# アプリ内アップデートのダイアログにもこの文章がそのまま表示される。
set -euo pipefail

VERSION="${1:?usage: release-notes.sh <version>}"
VERSION="${VERSION#v}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# "## [x.y.z]" から次の "## [" までを、見出し行を除いて取り出す
section() {
    local file="$1"
    awk -v ver="## [$VERSION]" '
        index($0, ver) == 1 { found = 1; next }
        found && /^## \[/    { exit }
        found                { print }
    ' "$file" | sed -e '/./,$!d' | awk 'BEGIN { blank = 0 }
        /^$/ { blank++; next }
        { while (blank-- > 0) print ""; blank = 0; print }
    '
}

zh="$(section "$REPO_DIR/CHANGELOG.md")"
en="$(section "$REPO_DIR/CHANGELOG.en.md")"

if [ -z "$zh" ] && [ -z "$en" ]; then
    echo "error: no changelog section found for version $VERSION" >&2
    exit 1
fi

cat <<EOF
## 更新内容（简体中文）

$zh

---

## What's Changed (English)

$en

---

完整更新日志 / Full changelog:
[CHANGELOG.md](https://github.com/Szyoo/cliptype/blob/main/CHANGELOG.md) ·
[English](https://github.com/Szyoo/cliptype/blob/main/CHANGELOG.en.md)
EOF
