#!/usr/bin/env bash
# LinuxBench - portable by default; system package installation requires opt-in.
set -uo pipefail
export LC_ALL=C
umask 077
VERSION=0.3.0
DISK_DIR="$PWD"; SIZE=128; NODE=all; ACCEPT=0; MODE=; FAILED=0; WORK=; RUNWORK=; DEP_MODE=; INSTALL_YES=0; VENDOR_DIR=; VENDOR_BUILD=; VENDOR_HASH=; VENDOR_BIN=
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
cleanup_all(){ cleanup; if [[ -n "$RUNWORK" ]]; then rm -rf -- "$RUNWORK"; fi; }
trap cleanup_all EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
usage(){ cat <<'EOF'
LinuxBench 0.3.0
  No arguments: interactive menu (requires controlling TTY)
  --portable            No package installation (default for direct flags)
  --install-mode        Permit installing missing open-source dependencies (APT)
  --vendor-dir DIR      Local approved dependency archive root
  --vendor-build ID     Explicit archived build ID
  --vendor-hash SHA256  Independently approved manifest hash
  --yes                 Confirm package installation non-interactively
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
Portable mode never installs packages. Install mode uses configured APT sources;
network tests still require an independently verified official Ookla CLI.
Portable mode cleans wrapper-owned temporary files; system logs may remain.
EOF
}
choose(){ [[ -z "$MODE" ]] || die "Choose exactly one mode"; MODE="$1"; }
dep_choose(){ [[ -z "$DEP_MODE" || "$DEP_MODE" == "$1" ]] || die "Conflicting dependency modes"; DEP_MODE="$1"; }
load_vendor(){
  [[ "$DEP_MODE" == portable ]] || return 0
  case "$MODE" in quick|nodes) return 0;; esac
  local arch manifest a tool sha path actual
  local -A seen=()
  case "$(uname -m)" in x86_64) arch=amd64;; aarch64) arch=arm64;; *) fail "Unsupported portable architecture"; return 1;; esac
  [[ -n "$VENDOR_DIR" && "$VENDOR_BUILD" =~ ^[0-9]+-[0-9]+$ && "$VENDOR_HASH" =~ ^[a-f0-9]{64}$ ]] || { fail "Portable benchmarks require an approved local archive (--vendor-dir, --vendor-build, --vendor-hash); no unverified fallback"; return 1; }
  manifest="$VENDOR_DIR/vendor/manifests/$VENDOR_BUILD.$arch.tsv"
  prepare_runwork || return 1
  cp -- "$manifest" "$RUNWORK/manifest" || return 1
  printf '%s  %s\n' "$VENDOR_HASH" "$RUNWORK/manifest" | sha256sum -c - || return 1
  VENDOR_BIN="$RUNWORK/bin"
  mkdir -m 700 -- "$VENDOR_BIN" || return 1
  while IFS='|' read -r a tool sha path; do
    [[ "$a" == "$arch" && "$sha" =~ ^[a-f0-9]{64}$ ]] || return 1
    case "$tool:$path" in
      jq:vendor/github.com/jqlang/jq/*/"$arch"/"$VENDOR_BUILD"/jq|fio:vendor/github.com/axboe/fio/*/"$arch"/"$VENDOR_BUILD"/fio|sysbench:vendor/github.com/akopytov/sysbench/*/"$arch"/"$VENDOR_BUILD"/sysbench) ;;
      *) return 1;;
    esac
    [[ "$path" != *..* && -z "${seen[$tool]:-}" ]] || return 1
    seen[$tool]=1
    cp -- "$VENDOR_DIR/$path" "$VENDOR_BIN/$tool" || return 1
    printf '%s  %s\n' "$sha" "$VENDOR_BIN/$tool" | sha256sum -c - || return 1
    chmod 700 "$VENDOR_BIN/$tool" || return 1
  done < "$RUNWORK/manifest"
  [[ ${#seen[@]} == 3 ]] || return 1
  export PATH="$VENDOR_BIN:$PATH"
}
install_deps(){
  [[ "$DEP_MODE" == install ]] || return 0
  local -a packages=() elevate=()
  case "$MODE" in
    standard|full|disk) has fio || packages+=(fio); has jq || packages+=(jq);;
  esac
  case "$MODE" in
    standard|full|cpu|memory) has sysbench || packages+=(sysbench);;
  esac
  case "$MODE" in
    standard|full|network) if ! has jq && [[ " ${packages[*]} " != *" jq "* ]]; then packages+=(jq); fi;;
  esac
  case "$MODE" in
    standard|full|cpu|memory|disk|network) has timeout || packages+=(coreutils);;
  esac
  (( ${#packages[@]} )) || return 0
  has apt-get || { fail "Install mode currently supports APT only"; return 1; }
  if (( EUID != 0 )); then has sudo || { fail "APT requires root or sudo"; return 1; }; elevate=(sudo); fi
  printf "Missing packages: %s\n" "${packages[*]}"
  warn "APT uses configured sources; dependencies may be installed or upgraded and remain on disk. No repository changes or automatic apt update."
  if (( ! INSTALL_YES )); then
    local reply
    if ! { exec 3<>/dev/tty; } 2>/dev/null; then fail "Use --yes to authorize package installation without a TTY"; return 1; fi
    printf "Install these packages? [y/N] " >&3
    read -r reply <&3 || reply=; exec 3>&-
    [[ "$reply" == y || "$reply" == Y ]] || { fail "Installation declined"; return 1; }
  fi
  "${elevate[@]}" apt-get install -y --no-install-recommends --no-remove "${packages[@]}" || { fail "APT failed; no automatic source or package-list changes attempted"; return 1; }
}
prepare_runwork(){
  [[ -n "$RUNWORK" ]] && return 0
  RUNWORK=$(mktemp -d -- "${TMPDIR:-/tmp}/linuxbench.XXXXXXXX") || { fail "Temporary directory creation failed"; return 1; }
  mkdir -p -- "$RUNWORK/home" "$RUNWORK/config" "$RUNWORK/cache" "$RUNWORK/data" "$RUNWORK/state" "$RUNWORK/tmp" || { fail "Temporary setup failed"; return 1; }
}
ookla(){
  env HOME="$RUNWORK/home" XDG_CONFIG_HOME="$RUNWORK/config" XDG_CACHE_HOME="$RUNWORK/cache" XDG_DATA_HOME="$RUNWORK/data" XDG_STATE_HOME="$RUNWORK/state" TMPDIR="$RUNWORK/tmp" "$@"
}
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
  prepare_runwork || return
  version=$(ookla timeout -k 2s 5s speedtest --version 2>/dev/null) || { fail "Cannot identify speedtest"; return; }
  [[ "$version" == *"Ookla"* ]] || { fail "Not the official Ookla CLI (version check only, not provenance verification)"; return; }
  printf "%-23s %12s %12s %10s %10s\n" "Target" "Down Mbps" "Up Mbps" "RTT ms" "Data MiB"
  for row in "${NODES[@]}"; do
    IFS="|" read -r key city id provider <<< "$row"
    [[ "$NODE" == all || "$NODE" == "$key" ]] || continue
    count=$((count+1))
    if result=$(ookla timeout -k 5s 90s speedtest --accept-license --accept-gdpr --progress=no --format=json --server-id="$id" 2>/dev/null) &&
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
  if [[ -z "$DEP_MODE" ]]; then
    printf "\nLinuxBench %s - execution mode\n1) Portable (no package installation)\n2) Install mode (APT, explicit consent)\n0) Exit\nSelect [1]: " "$VERSION" >&3
    read -r choice <&3 || choice=0
    case "$choice" in 1|"") DEP_MODE=portable;; 2) DEP_MODE=install;; 0) exit 0;; *) die "Invalid execution mode";; esac
  fi
  printf "\nLinuxBench %s\n1) Quick / system info\n2) Standard\n3) Full\n4) Disk\n5) CPU\n6) Memory\n7) Network (9 locations)\n8) List nodes\n0) Exit\nSelect: " "$VERSION" >&3
  read -r choice <&3 || choice=; exec 3>&-
  case "$choice" in 1) MODE=quick;; 2) MODE=standard;; 3) MODE=full;; 4) MODE=disk;; 5) MODE=cpu;; 6) MODE=memory;; 7) MODE=network;; 8) MODE=nodes;; 0) exit 0;; *) die "Invalid selection";; esac
}
while (( $# )); do
  case "$1" in
    --portable|--no-install) dep_choose portable;;
    --install-mode) dep_choose install;;
    --yes) INSTALL_YES=1;;
    --vendor-dir) (( $# >= 2 )) || die "Missing vendor directory"; VENDOR_DIR="$2"; shift;;
    --vendor-build) (( $# >= 2 )) || die "Missing build ID"; VENDOR_BUILD="$2"; shift;;
    --vendor-hash) (( $# >= 2 )) || die "Missing manifest hash"; VENDOR_HASH="$2"; shift;;
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
DEP_MODE=${DEP_MODE:-portable}
[[ "$DEP_MODE" == install || "$INSTALL_YES" == 0 ]] || die "--yes requires --install-mode"
load_vendor || die "Portable dependency verification failed"
install_deps || exit "$FAILED"
case "$MODE" in
  quick) info;; standard) info; disk 0; cpu 0; network;;
  full) info; disk 1; cpu 1; memory; network;;
  disk) disk 1;; cpu) cpu 1;; memory) memory;; network) network;; nodes) list_nodes;;
esac
exit "$FAILED"
