#!/bin/sh
set -eu
export LC_ALL=C
root=${1:?artifact root}
arch=${2:?architecture}
d=$(mktemp -d)
trap 'rm -rf "$d"' EXIT HUP INT TERM
while IFS='|' read -r a tool sha path; do
  [ "$a" = "$arch" ] || continue
  printf '%s  %s\n' "$sha" "$root/$path" | sha256sum -c -
  cp "$root/$path" "$d/$tool"
  chmod 700 "$d/$tool"
done < "$root/manifest.$arch.tsv"
"$d/jq" -en '1+2==3'
"$d/sysbench" cpu --threads=1 --time=1 --cpu-max-prime=1000 run
"$d/sysbench" memory --threads=1 --time=1 --memory-block-size=1M --memory-total-size=16M run
for rw in write read randwrite randread; do
  "$d/fio" --name=smoke --filename="$d/data" --size=8m --rw="$rw" --bs=4k --direct=1 --ioengine=sync --iodepth=1 --numjobs=1 --output-format=json --output="$d/result.json"
  "$d/jq" -e '.jobs[0].error==0' "$d/result.json"
done
