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
cp "$repo_root/lib/clavichord/mcp.sh" "$tmp_dir/lib/clavichord/mcp.sh"
chmod +x "$tmp_dir/bin/testproject"

cat > "$tmp_dir/lib/testproject/actions.d/mcp.sh" <<'ACTIONS'
set_action "show:" "instance tail? -v --format= -q=" "Show logs"
show(){
    echo "instance=$instance"
    echo "tail=${tail:-}"
    echo "v=${v:-0}"
    echo "format=${format:-}"
    echo "q=${q:-}"
    echo "extra=$*"
}

set_action "restart~?" "instance" "Restart instance"
restart(){ echo "restart $instance"; }

set_action "fail!" "" "Fail loudly"
fail(){
    echo "stdout failure"
    echo "stderr failure" >&2
    return 7
}

set_action "touch~" "" "Touch mutable state"
touch(){
    echo "touch extra=$*"
}
ACTIONS

run_mcp(){
    "$tmp_dir/bin/testproject" mcp "$@"
}

call_message(){
    local id="$1"
    local name="$2"
    local args="$3"

    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}\n' \
        "$id" \
        "$name" \
        "$args"
}

messages="$(
    printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"show","arguments":{"instance":"app","tail":"100","v":2,"format":"json","q":"quiet"}}}' \
        '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"restart","arguments":{"instance":"app"}}}' \
        '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"restart","arguments":{"instance":"app","confirm":true}}}' \
        '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"fail","arguments":{"confirm":true}}}' \
        '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"missing","arguments":{}}}' \
    | run_mcp
)"

if [ "$(printf "%s\n" "$messages" | wc -l)" -ne 7 ]; then
    echo "Expected exactly 7 JSON-RPC responses" >&2
    printf "%s\n" "$messages" >&2
    exit 1
fi

printf "%s\n" "$messages" | jq -e -s '
    .[0].id == 1
    and .[0].result.capabilities.tools == {}
    and .[1].id == 2
    and (.[1].result.tools[] | select(.name == "show")
        | .description == "Show logs"
        and .inputSchema.properties.instance.type == "string"
        and .inputSchema.properties.tail.type == "string"
        and .inputSchema.properties.v.type == "integer"
        and .inputSchema.properties.v.default == 0
        and .inputSchema.properties.format.type == "string"
        and .inputSchema.properties.q.type == "string"
        and .inputSchema.required == ["instance"]
        and .annotations.readOnlyHint == true
        and .annotations.destructiveHint == false)
    and (.[1].result.tools[] | select(.name == "restart")
        | .inputSchema.properties.confirm.type == "boolean"
        and .inputSchema.properties.confirm.description == "Must be true to execute this action."
        and (.inputSchema.required | index("confirm"))
        and .annotations.readOnlyHint == false
        and .annotations.destructiveHint == false)
    and (.[1].result.tools[] | select(.name == "fail")
        | .annotations.destructiveHint == true)
    and (.[2].result.content[0].text | contains("instance=app")
        and contains("tail=100")
        and contains("v=2")
        and contains("format=json")
        and contains("q=quiet"))
    and .[3].result.content[0].text == "Refusing to run '\''restart'\'' without confirm=true."
    and .[4].result.content[0].text == "restart app"
    and .[5].result.isError == true
    and (.[5].result.content[0].text | contains("stdout failure") and contains("stderr failure"))
    and .[6].result.isError == true
    and .[6].result.content[0].text == "Unknown tool: missing"
' >/dev/null

read_only_messages="$(
    {
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
        call_message 2 show '{"instance":"app"}'
        call_message 3 restart '{"instance":"app","confirm":true}'
    } | run_mcp --read-only
)"

printf "%s\n" "$read_only_messages" | jq -e -s '
    (.[0].result.tools | length) == 5
    and (.[0].result.tools[] | select(.name == "restart"))
    and .[1].result.content[0].text == "instance=app\ntail=\nv=0\nformat=\nq=\nextra="
    and .[2].result.isError == true
    and .[2].result.content[0].text == "Refusing to run '\''restart'\'' because MCP read-only mode is active."
' >/dev/null

deny_destructive_messages="$(
    {
        call_message 1 restart '{"instance":"app","confirm":true}'
        call_message 2 fail '{"confirm":true}'
    } | run_mcp --deny-destructive
)"

printf "%s\n" "$deny_destructive_messages" | jq -e -s '
    .[0].result.content[0].text == "restart app"
    and .[1].result.isError == true
    and .[1].result.content[0].text == "Refusing to run '\''fail'\'' because destructive actions are denied."
' >/dev/null

confirm_mutating_messages="$(
    {
        printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
        call_message 2 touch '{}'
        call_message 3 touch '{"confirm":true}'
        call_message 4 restart '{"instance":"app"}'
    } | run_mcp --confirm-mutating
)"

printf "%s\n" "$confirm_mutating_messages" | jq -e -s '
    (.[0].result.tools[] | select(.name == "touch")
        | .inputSchema.properties.confirm.type == "boolean"
        and .inputSchema.properties.confirm.description == "Must be true to execute this action."
        and (.inputSchema.required | index("confirm")))
    and .[1].result.content[0].text == "Refusing to run '\''touch'\'' without confirm=true."
    and .[2].result.content[0].text == "touch extra="
    and .[3].result.content[0].text == "Refusing to run '\''restart'\'' without confirm=true."
' >/dev/null

if printf '%s\n' '{}' | run_mcp --unknown >"$tmp_dir/unknown.out" 2>"$tmp_dir/unknown.err"; then
    echo "Unknown MCP option unexpectedly succeeded" >&2
    exit 1
fi

if [ -s "$tmp_dir/unknown.out" ]; then
    echo "Unknown MCP option wrote to stdout" >&2
    exit 1
fi

if ! grep -Fx "ERROR: unknown MCP option: --unknown" "$tmp_dir/unknown.err" >/dev/null; then
    echo "Unknown MCP option error missing" >&2
    cat "$tmp_dir/unknown.err" >&2
    exit 1
fi

normal_output="$("$tmp_dir/bin/testproject" show app 100 -v --format json -q quiet)"
if [ "$normal_output" != "instance=app
tail=100
v=1
format=json
q=quiet
extra=" ]; then
    echo "Normal CLI parsing changed unexpectedly" >&2
    printf "%s\n" "$normal_output" >&2
    exit 1
fi

mcp_argument_output="$("$tmp_dir/bin/testproject" show app mcp)"
if [ "$mcp_argument_output" != "instance=app
tail=mcp
v=0
format=
q=
extra=" ]; then
    echo "Normal CLI treated a later mcp argument as MCP mode" >&2
    printf "%s\n" "$mcp_argument_output" >&2
    exit 1
fi

echo "mcp stdio tests passed"
