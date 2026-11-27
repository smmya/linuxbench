# Vendored dependencies

Target layout (examples, not claims of existing binaries or approved versions):

```
vendor/
  github.com/jqlang/jq/<upstream-version>/<architecture>/<original-filename>
  github.com/axboe/fio/<upstream-version>/<architecture>/<original-filename>
  github.com/akopytov/sysbench/<upstream-version>/<architecture>/<original-filename>
  install.speedtest.net/app/cli/<upstream-version>/<architecture>/<original-filename>
  manifest.tsv
```

Preserve upstream owner/project, original filename, exact upstream version, architecture, and source URL. For distribution-built packages also record distribution, release, package revision, ABI and dependency closure. Do not rename different builds into one version.

Each approved artifact needs SHA-256 of original archive and executable, upstream provenance/signature evidence, redistribution license, corresponding source location (and source distribution where required), review date, architecture and runtime ABI. Record these in a reviewed manifest pinned to the LinuxBench release. Reject missing entries, mismatches and unsupported architecture/ABI; never silently fetch latest or an alternate mirror. A hash alone does not establish safety.

Portable: select a reviewed artifact, verify before extraction, extract only approved regular files into a private temporary workspace, run without root and with isolated HOME/XDG paths, and clean workspace on exit. Dynamic dependencies need an audited compatible bundle; do not use host package installation as an implicit fallback. Do not use unverified archives or execute package maintainer scripts.

Install: use configured trusted distribution package manager for missing open-source dependencies with explicit permission. Do not install unverified Ookla packages.

No binary files have been imported yet. Ookla redistribution permission must be established before public vendoring; otherwise retain metadata and allow an independently verified user-provided official artifact. Do not claim the portable bundle is complete until artifacts, licensing, checksums and execution tests are verified.
