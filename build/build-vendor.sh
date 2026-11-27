#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
umask 022
cd "$(dirname "$0")/.."
root=$PWD
arch=${1:?architecture required}
build_id=${2:?build ID required}
filter=${3:-all}
case "$filter" in all|jq|musl) ;; *) exit 2;; esac
[[ "$arch" == amd64 || "$arch" == arm64 ]]
[[ "$build_id" =~ ^[0-9]+-[0-9]+$ ]]
case "$arch:$(uname -m)" in amd64:x86_64|arm64:aarch64) ;; *) echo "Native runner architecture mismatch"; exit 1;; esac
out="$root/out"
mkdir -p "$out"
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
export CFLAGS="-O2 -fcommon"
export CXXFLAGS="-O2"
case "$arch" in amd64) export CFLAGS="$CFLAGS -march=x86-64 -mtune=generic";; arm64) export CFLAGS="$CFLAGS -march=armv8-a";; esac
jobs=$(nproc)
(( jobs <= 4 )) || jobs=4
while IFS='|' read -r tool project version commit; do
  [[ "$tool" == \#* || -z "$tool" ]] && continue
  case "$filter:$tool" in jq:jq|musl:fio|musl:sysbench|all:*) ;; *) continue;; esac
  [[ "$commit" =~ ^[a-f0-9]{40}$ ]]
  src="$scratch/$tool"
  git init "$src"
  git -C "$src" remote add origin "https://github.com/$project.git"
  git -C "$src" fetch --depth=1 origin "$commit"
  git -C "$src" checkout --detach FETCH_HEAD
  [[ "$(git -C "$src" rev-parse HEAD)" == "$commit" ]]
  git -C "$src" -c protocol.file.allow=never submodule update --init --recursive
  dest="$out/vendor/github.com/$project/$version/$arch/$build_id"
  mkdir -p "$dest"
  {
    printf 'project=https://github.com/%s\nversion=%s\ncommit=%s\narchitecture=%s\nbuild=%s\n' "$project" "$version" "$commit" "$arch" "$build_id"
    printf 'builder_image=%s\nCFLAGS=%s\n' "${BUILDER_IMAGE_ID:-unknown}" "$CFLAGS"
    git -C "$src" submodule status --recursive
    cc --version
    if command -v apk >/dev/null; then apk info -vv; else dpkg-query -W; fi
  } > "$dest/BUILDINFO"
  # Preserve corresponding upstream source, including bundled libraries, before build.
  tar -C "$src" --exclude=.git -czf "$dest/source.tar.gz" .
  (
    cd "$src"
    case "$tool" in
      jq)
        autoreconf -fi
        ./configure --with-oniguruma=builtin --disable-maintainer-mode --disable-shared --enable-static
        make -j"$jobs" LDFLAGS=-all-static
        if ! make check LDFLAGS=-all-static; then
          for log in test-suite.log tests/jqtest.log tests/shtest.log; do
            if [[ -f "$log" ]]; then printf "\n=== %s ===\n" "$log"; cat "$log"; fi
          done
          exit 1
        fi
        cp jq "$dest/jq"
        ;;
      fio)
        ./configure --extra-cflags="$CFLAGS" --build-static --disable-native --disable-numa --disable-rdma --disable-rados --disable-rbd --disable-http --disable-gfapi --disable-pmem --disable-lex
        make -j"$jobs"
        cp fio "$dest/fio"
        ;;
      sysbench)
        ./autogen.sh
        ./configure --without-mysql --without-pgsql --disable-aio LDFLAGS=-static
        make -j"$jobs" LDFLAGS=-static
        cp src/sysbench "$dest/sysbench"
        ;;
      *) exit 1;;
    esac
    for file in LICENSE LICENSE.md COPYING COPYRIGHT; do
      [[ ! -f "$file" ]] || cp "$file" "$dest/"
    done
  )
  strip "$dest/$tool"
  # A portable binary must not request a dynamic loader or shared library.
  readelf -h "$dest/$tool" > "$dest/ELFINFO"
  if readelf -l "$dest/$tool" | grep -q INTERP; then echo "Dynamic interpreter found"; exit 1; fi
  if readelf -d "$dest/$tool" | grep -q '(NEEDED)'; then echo "Shared library dependency found"; exit 1; fi
  "$dest/$tool" --version
  if command -v apk >/dev/null; then
    cp /usr/share/licenses/musl/COPYRIGHT "$dest/MUSL-COPYRIGHT" 2>/dev/null || :
  else
    cp /usr/share/doc/libc6/copyright "$dest/GLIBC-COPYRIGHT"
  fi
  (cd "$dest"; sha256sum "$tool" source.tar.gz > SHA256SUMS)
  printf '%s|%s|%s|%s\n' "$arch" "$tool" "$(sha256sum "$dest/$tool" | cut -d' ' -f1)" "${dest#"$out/"}/$tool" >> "$out/manifest.$arch.tsv"
done < "$root/build/sources.lock"
