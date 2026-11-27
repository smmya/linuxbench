#!/usr/bin/env bash
# LinuxBench - local benchmark runner; no automatic installation or downloads.
set -uo pipefail
export LC_ALL=C
umask 077
VERSION=0.1.0
DISK_DIR="$PWD"; SIZE=128; NODE=all; ACCEPT=0; MODE=; FAILED=0; WORK=
declare -a NODES=(
  "london|London, GB|35057|Clouvider"
  "frankfurt|Frankfurt, DE|35692|Clouvider"
  "los-angeles|Los Angeles, US|7190|historical upstream"
  "new-york|New York, US|35055|Clouvider"
  "shanghai|Shanghai, CN|24447|China Unicom (historical)"
  "guangzhou|Guangzhou, CN|27594|historical; unverified"
  "singapore|Singapore, SG|13623|upstream reference"
  "tokyo|Tokyo, JP|48463|upstream reference"
  "johannesburg|Johannesburg, ZA|61308|Angola Cables"
)
has(){ command -v "$1" >/dev/null 2>&1; }
warn(){ printf "[WARN] %s\n" "$*" >&2; }
fail(){ warn "$*"; FAILED=1; }
die(){ warn "$*"; exit 2; }
cleanup(){ if [[ -n "$WORK" ]]; then rm -rf -- "$WORK"; fi; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
usage(){ cat <<'EOF'
LinuxBench 0.1.0
  No arguments: interactive menu (requires controlling TTY)
  --quick / --info      Local system information only
  --standard           Information + sequential disk + single-core CPU + network
  --full               Information + disk incl. 4K + CPU + memory + network
  --disk / --cpu / --memory / --network
  --nodes              List fixed Speedtest server IDs
  --node CITY          Only selected network node (see --nodes)
  --disk-dir DIR       Existing writable target directory (default: current directory)
  --size-mib N         Disk test file size, 64..512 (default 128)
  --accept-ookla       Explicit consent to Ookla terms and network test traffic
  --version / --help
No packages installed or downloaded; network tests require an independently
trusted official Ookla CLI, jq, timeout, non-root user, and explicit consent.
EOF
}
choose(){ [[ -z "$MODE" ]] || die "Choose exactly one mode"; MODE="$1"; }
list_nodes(){ local row key city id provider; for row in "${NODES[@]}"; do IFS="|" read -r key city id provider <<< "$row"; printf "%-15s %-23s %-7s %s\n" "$key" "$city" "$id" "$provider"; done; }
info(){
  printf "\n=== SYSTEM ===\n"; uname -srmo
  if [[ -r /etc/os-release ]]; then grep "^PRETTY_NAME=" /etc/os-release || :; fi
  if has lscpu; then lscpu | grep -E "^(Architecture|CPU\(s\)|Model name|Thread\(s\) per core|Core\(s\) per socket|Socket\(s\)|CPU MHz|CPU max MHz|Hypervisor vendor|Virtualization type):" || :; fi
  if has nproc; then printf "Available logical CPUs: "; nproc; fi
  if has free; then free -h; fi
  if has systemd-detect-virt; then printf "Virtualization: "; systemd-detect-virt || :; fi
  if has uptime; then uptime; fi
  if [[ -r /proc/sys/net/ipv4/tcp_congestion_control ]]; then printf "TCP congestion control: "; cat /proc/sys/net/ipv4/tcp_congestion_control; fi
  if [[ -r /proc/self/cgroup ]]; then
    local cg f p; cg=$(awk -F: '$1=="0" {print $3; exit}' /proc/self/cgroup)
    if [[ "$cg" == /* && "$cg" != *..* ]]; then
      for f in cpu.max memory.max memory.current; do p="/sys/fs/cgroup${cg%/}/$f"; [[ -r "$p" ]] || p="/sys/fs/cgroup/$f"; if [[ -r "$p" ]]; then printf "cgroup %s: " "$f"; cat "$p"; fi; done
    fi
  fi
  if has lsblk; then lsblk -o NAME,TYPE,SIZE,ROTA,TRAN,MODEL,FSTYPE,MOUNTPOINT || :; fi
  df -hT -- "$DISK_DIR" || :
}
prepare_disk(){
  local free_k type target
  [[ -d "$DISK_DIR" && -w "$DISK_DIR" ]] || { fail "Disk directory not writable"; return 1; }
  target=$(cd -- "$DISK_DIR" && pwd -P) || return 1
  type=$(stat -f -c %T -- "$target") || return 1
  case "$type" in tmpfs|ramfs|nfs|nfs4|cifs|smb2|fuse*|proc|sysfs) fail "Unsafe or non-local disk target: $type"; return 1;; esac
  free_k=$(df -Pk -- "$target" | awk 'NR==2 {print $4}')
  [[ "$free_k" =~ ^[0-9]+$ ]] || { fail "Cannot determine free space"; return 1; }
  (( free_k >= (SIZE+1024)*1024 )) || { fail "Need test size plus at least 1 GiB free"; return 1; }
  WORK=$(mktemp -d -- "$target/.linuxbench.XXXXXXXX") || { fail "mktemp failed"; return 1; }
}
disk(){
  local full="$1" rw bs
  printf "\n=== DISK (%s MiB; temporary file only) ===\n" "$SIZE"
  has fio && has timeout && has jq || { fail "Disk requires fio, timeout and jq from trusted packages"; return; }
  prepare_disk || return
  local -a tests=(write read); [[ "$full" == 1 ]] && tests+=(randwrite randread)
  for rw in "${tests[@]}"; do
    bs=1M; [[ "$rw" == rand* ]] && bs=4k
    if ! timeout -k 5s 45s fio --name=linuxbench --filename="$WORK/test.bin" --size="${SIZE}m" --rw="$rw" --bs="$bs" --direct=1 --ioengine=sync --iodepth=1 --numjobs=1 --refill_buffers=1 --end_fsync=1 --output-format=json --output="$WORK/fio.json" >/dev/null 2>&1; then fail "fio $rw failed or timed out"; break; fi
    if ! jq -er --arg rw "$rw" '.jobs[0] | select(.error==0) | (if ($rw|endswith("write")) then .write else .read end) | "\($rw): \(.bw_bytes/1048576) MiB/s, \(.iops) IOPS"' "$WORK/fio.json"; then fail "Invalid fio result"; break; fi
  done
  cleanup; WORK=
}
cpu(){
  local full="$1" threads=1
  printf "\n=== CPU ===\n"
  has sysbench && has timeout || { fail "CPU requires sysbench and timeout"; return; }
  timeout -k 3s 15s sysbench cpu --threads=1 --time=5 --cpu-max-prime=20000 run || fail "Single-core test failed"
  if [[ "$full" == 1 ]]; then
    threads=$(nproc 2>/dev/null || printf 1); [[ "$threads" =~ ^[1-9][0-9]*$ ]] || threads=1
    (( threads > 8 )) && threads=8
    timeout -k 3s 15s sysbench cpu --threads="$threads" --time=5 --cpu-max-prime=20000 run || fail "Multi-core test failed"
  fi
}
memory(){
  printf "\n=== MEMORY ===\n"
  has sysbench && has timeout || { fail "Memory requires sysbench and timeout"; return; }
  timeout -k 3s 15s sysbench memory --threads=1 --time=5 --memory-block-size=1M --memory-total-size=1T --memory-oper=write run || fail "Memory test failed"
}
network(){
  local row key city id provider version result line count=0
  printf "\n=== NETWORK (Ookla) ===\n"
  (( EUID != 0 )) || { fail "Run network tests as a regular user, not root"; return; }
  has speedtest && has jq && has timeout || { fail "Install and verify official Ookla speedtest separately; jq and timeout also required"; return; }
  if (( ! ACCEPT )); then
    warn "Network tests transfer potentially many GB; Ookla may collect IP and results. Terms: https://www.speedtest.net/about/eula ; https://www.speedtest.net/about/privacy"
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then fail "Explicit --accept-ookla required"; return; fi
    printf "Accept applicable Ookla terms and run network tests? [y/N] " >&3
    read -r line <&3 || line=; exec 3>&-
    [[ "$line" == y || "$line" == Y ]] || { fail "Network declined"; return; }
  fi
  version=$(timeout -k 2s 5s speedtest --version 2>/dev/null) || { fail "Cannot identify speedtest"; return; }
  [[ "$version" == *"Ookla"* ]] || { fail "Not the official Ookla CLI (version check only, not provenance verification)"; return; }
  printf "%-23s %12s %12s %10s %10s\n" "Target" "Down Mbps" "Up Mbps" "RTT ms" "Data MiB"
  for row in "${NODES[@]}"; do
    IFS="|" read -r key city id provider <<< "$row"
    [[ "$NODE" == all || "$NODE" == "$key" ]] || continue
    count=$((count+1))
    if result=$(timeout -k 5s 90s speedtest --accept-license --accept-gdpr --progress=no --format=json --server-id="$id" 2>/dev/null) &&
       line=$(jq -er --arg id "$id" 'select(.type=="result" and (.server.id|tostring)==$id and (.download.bandwidth|type)=="number" and (.upload.bandwidth|type)=="number" and (.ping.latency|type)=="number" and (.download.bytes|type)=="number" and (.upload.bytes|type)=="number") | [.download.bandwidth*8/1000000,.upload.bandwidth*8/1000000,.ping.latency,(.download.bytes+.upload.bytes)/1048576] | @tsv' <<< "$result"); then
      local down up rtt bytes; IFS=$'\t' read -r down up rtt bytes <<< "$line"
      printf "%-23s %12.2f %12.2f %10.2f %10.2f\n" "$city" "$down" "$up" "$rtt" "$bytes"
    else
      fail "$city (ID $id): unavailable, timeout or invalid response; no cross-city fallback"
    fi
  done
  (( count > 0 )) || fail "Unknown node: $NODE"
}
menu(){
  local choice
  if ! { exec 3<>/dev/tty; } 2>/dev/null; then usage; die "No terminal; specify a mode"; fi
  printf "\nLinuxBench %s\n1) Quick / system info\n2) Standard\n3) Full\n4) Disk\n5) CPU\n6) Memory\n7) Network (9 locations)\n8) List nodes\n0) Exit\nSelect: " "$VERSION" >&3
  read -r choice <&3 || choice=; exec 3>&-
  case "$choice" in 1) MODE=quick;; 2) MODE=standard;; 3) MODE=full;; 4) MODE=disk;; 5) MODE=cpu;; 6) MODE=memory;; 7) MODE=network;; 8) MODE=nodes;; 0) exit 0;; *) die "Invalid selection";; esac
}
while (( $# )); do
  case "$1" in
    --quick|--info) choose quick;;
    --standard|--full|--disk|--cpu|--memory|--network|--nodes) choose "${1#--}";;
    --disk-dir) (( $# >= 2 )) || die "Missing directory"; DISK_DIR="$2"; shift;;
    --size-mib) (( $# >= 2 )) || die "Missing size"; SIZE="$2"; shift;;
    --node) (( $# >= 2 )) || die "Missing node"; NODE="$2"; shift;;
    --accept-ookla) ACCEPT=1;;
    --help|-h) usage; exit 0;;
    --version) printf "%s\n" "$VERSION"; exit 0;;
    *) die "Unknown option: $1";;
  esac; shift
done
[[ "$SIZE" =~ ^[1-9][0-9]{1,2}$ ]] && (( SIZE >= 64 && SIZE <= 512 )) || die "Size must be 64..512 MiB"
if [[ "$NODE" != all ]]; then
  valid=0; for row in "${NODES[@]}"; do [[ "${row%%|*}" == "$NODE" ]] && valid=1; done
  (( valid )) || die "Unknown node: $NODE"
fi
[[ -n "$MODE" ]] || menu
case "$MODE" in
  quick) info;; standard) info; disk 0; cpu 0; network;;
  full) info; disk 1; cpu 1; memory; network;;
  disk) disk 1;; cpu) cpu 1;; memory) memory;; network) network;; nodes) list_nodes;;
esac
exit "$FAILED"
