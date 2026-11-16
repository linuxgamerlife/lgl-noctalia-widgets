#!/usr/bin/env bash
# Validate the seven root plugin directories with the Noctalia community
# validator. The validator is run against a staging directory so only plugin
# payloads are checked.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PLUGINS=(
    ai-usage
    dualsense
    kbm-overlay
    modern-sysmonitor-plus
    steam-controller
    steamdb-stats
    weather-time
)

find_validator() {
    if [ -n "${COMMUNITY_VALIDATOR:-}" ]; then
        printf '%s\n' "$COMMUNITY_VALIDATOR"
        return 0
    fi
    local candidates=(
        "$REPO_ROOT/../official-plugins/.github/workflows/validate-plugins.py"
        "/development/projects/noctalia/official-plugins/.github/workflows/validate-plugins.py"
        "$HOME/.config/noctalia/noctalia/plugins/sources/community/repo/.github/workflows/scripts/validate-plugins.py"
        "$HOME/.local/state/noctalia/plugins/sources/community/repo/.github/workflows/scripts/validate-plugins.py"
    )
    local candidate
    for candidate in "${candidates[@]}"; do
        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

VALIDATOR="$(find_validator)" || {
    echo "error: community validator not found." >&2
    echo "Set COMMUNITY_VALIDATOR to validate-plugins.py and rerun." >&2
    exit 1
}

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/lgl-noctalia-validate.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

for plugin in "${PLUGINS[@]}"; do
    if [ ! -f "$REPO_ROOT/$plugin/plugin.toml" ]; then
        echo "error: missing $plugin/plugin.toml" >&2
        exit 1
    fi
    cp -a "$REPO_ROOT/$plugin" "$STAGE/"
done

python3 "$VALIDATOR" --root "$STAGE"
