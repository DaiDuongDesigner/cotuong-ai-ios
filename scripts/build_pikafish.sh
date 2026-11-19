#!/bin/bash
# Biên dịch Pikafish (GPL-3.0) thành thư viện tĩnh cho iPhone (arm64) + tải mạng NNUE.
# Chạy trên macOS (GitHub Actions). Kết quả: Pikafish/libpikafish.a, Resources/pikafish.nnue
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build-pikafish"
rm -rf "$WORK" && mkdir -p "$WORK/obj"
git clone --depth 1 https://github.com/official-pikafish/Pikafish.git "$WORK/src-repo"
SRC="$WORK/src-repo/src"
echo "Pikafish commit: $(git -C "$WORK/src-repo" log -1 --format='%h %cd')"

# Mạng NNUE (đúng phiên bản với mã nguồn vừa tải)
( cd "$SRC" && sh ../scripts/net.sh )
cp "$SRC/pikafish.nnue" "$ROOT/Resources/pikafish.nnue"
ls -lh "$ROOT/Resources/pikafish.nnue"

# Không cho engine gọi exit() – sẽ đóng cả app.
for f in nnue/network.cpp uci.cpp misc.cpp; do
  sed -i '' -e 's/std::exit(1);/pikafish_fatal();/g' -e 's/std::exit(EXIT_FAILURE);/pikafish_fatal();/g' \
            -e 's/\([^_a-zA-Z]\)exit(EXIT_FAILURE);/\1pikafish_fatal();/g' "$SRC/$f"
  { echo 'extern "C" [[noreturn]] void pikafish_fatal(void);'; cat "$SRC/$f"; } > "$SRC/$f.tmp" && mv "$SRC/$f.tmp" "$SRC/$f"
  if grep -nE '(^|[^_a-zA-Z])exit\(' "$SRC/$f"; then echo "Còn exit() trong $f"; fi
done

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CXX="$(xcrun --sdk iphoneos --find clang++)"
FLAGS=(-arch arm64 -isysroot "$SDK" -miphoneos-version-min=16.0 -std=c++17 -O3 -DNDEBUG
       -DIS_64BIT -DUSE_POPCNT -DUSE_NEON=8 -fno-exceptions -w -I"$SRC" -I"$ROOT/Pikafish")

cd "$SRC"
FILES=$(find . \( -path ./universal -o -path ./temp_builds \) -prune -o -name '*.cpp' -print | grep -v '^\./main\.cpp$')
for f in $FILES; do echo "$f"; done > "$WORK/files.txt"
echo "$ROOT/Pikafish/PikafishBridge.cpp" >> "$WORK/files.txt"
export CXX WORK
printf '%s\0' "${FLAGS[@]}" > "$WORK/flags"
compile() {
  local f="$1" o
  o="$WORK/obj/$(echo "$f" | sed 's|[/.]|_|g').o"
  local -a fl=(); while IFS= read -r -d '' x; do fl+=("$x"); done < "$WORK/flags"
  "$CXX" "${fl[@]}" -c "$f" -o "$o"
}
export -f compile
xargs -P "$(sysctl -n hw.ncpu)" -I{} bash -c 'compile "$@"' _ {} < "$WORK/files.txt"
libtool -static -o "$ROOT/Pikafish/libpikafish.a" "$WORK"/obj/*.o
ls -lh "$ROOT/Pikafish/libpikafish.a"
