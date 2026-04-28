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
ACTIONS

run_mcp(){
    "$tmp_dir/bin/testproject" mcp
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

echo "mcp stdio tests passed"
