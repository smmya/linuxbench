# LinuxBench

Lightweight Bash benchmark runner for Linux servers. Initial development version 0.2.0; not yet production-validated.

## Usage

Download and inspect linuxbench.sh before running. No arguments opens an interactive menu using the controlling terminal.

```bash
bash linuxbench.sh
bash linuxbench.sh --quick
bash linuxbench.sh --disk --disk-dir /data --size-mib 256
bash linuxbench.sh --network --node tokyo
bash linuxbench.sh --network --accept-ookla
bash linuxbench.sh --help
```

## Dependencies

Bash and ordinary Linux utilities for system information. Optional fio, jq, sysbench and GNU timeout for benchmarks. Install these independently from trusted distribution packages; LinuxBench portable mode never installs packages; opt-in install mode can install missing packages using configured APT sources. Official Ookla Speedtest CLI is the sole proprietary dependency and must be obtained and verified independently from https://www.speedtest.net/apps/cli . A version string check is not cryptographic verification. Do not run network benchmarks as root. Do not use the unrelated Python speedtest-cli package.

Ookla usage is subject to applicable license and privacy terms. Explicit consent is required before running. Ookla may transmit IP and test results. Nine tests may consume many gigabytes; per-node timeout is not a hard traffic cap.

## Nodes

London, Frankfurt, Los Angeles, New York, Shanghai, Guangzhou, Singapore, Tokyo, Johannesburg. IDs in the script are provisional candidates, NOT live-verified. No automatic geographic fallback. Review provider and city before relying on measurements.

## Security

No remote executable download, automatic source modification or benchmark report upload by the wrapper itself. Install mode may change installed packages with consent. Disk tests use a private temporary file and require at least 1 GiB additional free space, but can still affect production workloads. CPU tests cap threads at eight. Network tests are sequential with timeouts. Neither third-party binaries nor dependencies have been independently audited here. The current implementation has not passed a live test matrix or ShellCheck yet. No signed release is available.

## Status

Early development. Test on disposable systems first. Debian 12/13 are initial compatibility targets. Node availability, geography, license terms, and actual resource consumption require verification.

## Execution modes (0.2.0)

No arguments opens a choice between portable and install mode, followed by the benchmark menu. CLI flags default to portable. Use `--portable --full`, `--install-mode --full` or `--install-mode --full --yes`. Install mode supports APT only, uses existing package indexes, and may leave installed dependencies. Ookla still requires an independently verified existing executable and a non-root user; its HOME and XDG paths are redirected to a temporary workspace. This is not a sandbox. Portable currently uses existing tools, not a complete vendored bundle. See [vendor policy](vendor/README.md). No binary has been uploaded and no live tests have been performed.

## Remote portable archives (0.4.0 development)

Remote portable dependencies are downloaded exclusively from raw.githubusercontent.com/smmya/linuxbench at an immutable commit, directly or through an explicitly selected HTTPS acceleration prefix. No geographic IP lookup is performed. Direct is the default. For mainland China select auto in the menu or use `--github-source auto`. Candidate prefixes: gh-proxy.com, ghfast.top, ghproxy.net; then direct, then an optional custom GAD-compatible prefix. Candidate availability is not guaranteed. Use `--github-source custom --github-proxy https://proxy.example.com` to use only a custom prefix, or `--no-proxy` to avoid acceleration. No credentials or query strings are accepted in proxy prefixes. Existing environment HTTP proxy settings may still apply.

Until a maintainer approves an archived build and embeds its commit/build/architecture-specific manifest hashes in the script, supply `--vendor-ref COMMIT --vendor-build RUN-ATTEMPT --vendor-hash SHA256` using independently verified values. The downloaded manifest and every binary are verified against the trusted hashes; mismatch causes refusal and route fallback. The initial LinuxBench script itself must be obtained from a trusted source and verified independently; do not bootstrap it blindly from an untrusted proxy. Local archives remain supported via --vendor-dir. Ookla is not yet vendored. No live network or compatibility validation is claimed for this change.
