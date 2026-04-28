#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp_dir="$(mktemp -d)"

cleanup(){
    rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p \
    "$tmp_dir/bin" \
    "$tmp_dir/lib/clavichord" \
    "$tmp_dir/lib/testproject/actions.d"

cp "$repo_root/clavichord" "$tmp_dir/bin/testproject"
cp "$repo_root/play.sh" "$tmp_dir/lib/clavichord/play.sh"
cp "$repo_root/config.sh" "$tmp_dir/lib/testproject/config.sh"
chmod +x "$tmp_dir/bin/testproject"

cat > "$tmp_dir/lib/testproject/actions.d/metadata.sh" <<'ACTIONS'
set_action "logs:" "" "Show logs"
logs(){ echo "logs called"; }

set_action "restart~?" "" "Restart instance"
restart(){ echo "restart called"; }

set_action "restore!?" "" "Restore snapshot"
restore(){ echo "restore called"; }

set_action "audit:trail:" "" "Audit trail"
audit:trail(){ echo "audit trail called"; }

set_action "ops~blue:" "" "Marker in middle"
set_action "ops!blue:" "" "Marker in middle"
set_action "ops?blue:" "" "Marker in middle"

set_action "legacy" "" "Legacy action"
legacy(){ echo "legacy called"; }
ACTIONS

run_project(){
    "$tmp_dir/bin/testproject" "$@"
}

assert_contains_line(){
    local haystack="$1"
    local needle="$2"

    if ! printf "%s\n" "$haystack" | grep -Fx "$needle" >/dev/null; then
        echo "Expected line not found: $needle" >&2
        echo "Output was:" >&2
        printf "%s\n" "$haystack" >&2
        exit 1
    fi
}

assert_not_contains_line(){
    local haystack="$1"
    local needle="$2"

    if printf "%s\n" "$haystack" | grep -Fx "$needle" >/dev/null; then
        echo "Unexpected line found: $needle" >&2
        echo "Output was:" >&2
        printf "%s\n" "$haystack" >&2
        exit 1
    fi
}

actions_output="$(run_project actions)"
metadata_output="$(run_project actions -m)"

assert_contains_line "$actions_output" "logs"
assert_contains_line "$actions_output" "restart"
assert_contains_line "$actions_output" "restore"
assert_contains_line "$actions_output" "audit:trail"
assert_contains_line "$actions_output" "ops~blue"
assert_contains_line "$actions_output" "ops!blue"
assert_contains_line "$actions_output" "ops?blue"
assert_contains_line "$actions_output" "legacy"
assert_not_contains_line "$actions_output" "logs:"
assert_not_contains_line "$actions_output" "restart~?"
assert_not_contains_line "$actions_output" "restore!?"
assert_not_contains_line "$actions_output" "audit:trail:"
assert_not_contains_line "$actions_output" "ops~blue:"
assert_not_contains_line "$actions_output" "ops!blue:"
assert_not_contains_line "$actions_output" "ops?blue:"

assert_contains_line "$metadata_output" "logs read_only=true mutating=false destructive=false requires_confirmation=false"
assert_contains_line "$metadata_output" "restart read_only=false mutating=true destructive=false requires_confirmation=true"
assert_contains_line "$metadata_output" "restore read_only=false mutating=true destructive=true requires_confirmation=true"
assert_contains_line "$metadata_output" "audit:trail read_only=true mutating=false destructive=false requires_confirmation=false"
assert_contains_line "$metadata_output" "ops~blue read_only=true mutating=false destructive=false requires_confirmation=false"
assert_contains_line "$metadata_output" "ops!blue read_only=true mutating=false destructive=false requires_confirmation=false"
assert_contains_line "$metadata_output" "ops?blue read_only=true mutating=false destructive=false requires_confirmation=false"
assert_contains_line "$metadata_output" "legacy read_only=false mutating=false destructive=false requires_confirmation=false"

if [ "$(run_project logs)" != "logs called" ]; then
    echo "logs action did not dispatch by normalized name" >&2
    exit 1
fi

if [ "$(run_project restart)" != "restart called" ]; then
    echo "restart action did not dispatch by normalized name" >&2
    exit 1
fi

if [ "$(run_project restore)" != "restore called" ]; then
    echo "restore action did not dispatch by normalized name" >&2
    exit 1
fi

if [ "$(run_project legacy)" != "legacy called" ]; then
    echo "legacy action did not dispatch" >&2
    exit 1
fi

echo "action metadata tests passed"
