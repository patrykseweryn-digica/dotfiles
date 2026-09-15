#!/bin/bash
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
task_dir="$(mktemp -d)"
trap 'rm -rf "$task_dir"' EXIT
mkdir -p "$task_dir/stubs" "$task_dir/package"
printf '#!/bin/sh\necho "treehouse v2.3.0"\n' > "$task_dir/package/treehouse"
chmod +x "$task_dir/package/treehouse"
tar czf "$task_dir/release.tar.gz" -C "$task_dir/package" treehouse
cat > "$task_dir/stubs/uname" <<'STUB'
#!/bin/sh
if [ "$1" = -s ]; then echo "$TEST_OS"; else echo "$TEST_ARCH"; fi
STUB
cat > "$task_dir/stubs/curl" <<'STUB'
#!/bin/bash
set -eu
printf '%s\n' "$*" >> "$TREEHOUSE_LOG"
case "$*" in
    *api.github.com*) echo 'API rate limit exceeded' >&2; exit 22 ;;
    *releases/latest*) echo 'https://github.com/kunchenguid/treehouse/releases/tag/v2.3.0' ;;
    *releases/download/v2.3.0/treehouse-v2.3.0-*.tar.gz*)
        [ "${FAIL_DOWNLOAD:-false}" = false ] || { echo 'download interrupted' >&2; exit 22; }
        while [ "$1" != -o ]; do shift; done
        cp "$TREEHOUSE_ARCHIVE" "$2" ;;
    *) echo "unexpected URL: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$task_dir/stubs/"*
export PATH="$task_dir/stubs:$PATH"
export TREEHOUSE_ARCHIVE="$task_dir/release.tar.gz" TREEHOUSE_LOG="$task_dir/calls"
# shellcheck source=bootstrap.d/05-tools.sh
source "$repo/bootstrap.d/05-tools.sh"
for TEST_OS in Linux Darwin; do
    for TEST_ARCH in x86_64 aarch64 arm64; do
        export TEST_OS TEST_ARCH
        BIN_DIR="$task_dir/$TEST_OS $TEST_ARCH home/.local/bin"
        export BIN_DIR
        install_treehouse > "$task_dir/output" 2>&1 || { cat "$task_dir/output"; exit 1; }
        [ "$("$BIN_DIR/treehouse" --version)" = 'treehouse v2.3.0' ]
        cp "$BIN_DIR/treehouse" "$task_dir/before"
        if FAIL_DOWNLOAD=true install_treehouse > "$task_dir/output" 2>&1; then
            echo 'Failed download passed' >&2; exit 1
        fi
        rg -q 'Treehouse' "$task_dir/output"
        cmp "$task_dir/before" "$BIN_DIR/treehouse"
        install_treehouse
    done
done
TEST_ARCH=riscv64
export TEST_ARCH
if install_treehouse > "$task_dir/output" 2>&1; then exit 1; fi
rg -q 'Unsupported.*Treehouse' "$task_dir/output"
echo '[INFO] Treehouse smoke test passed'
