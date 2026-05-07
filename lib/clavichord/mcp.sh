clavichord_mcp_json_bool(){
    if [ "$1" == true ]; then
        echo true
    else
        echo false
    fi
}

clavichord_mcp_arg_name(){
    local arg="$1"

    arg="${arg#--}"
    arg="${arg#-}"
    arg="${arg%\?}"
    arg="${arg%=}"
    arg="${arg%\?}"
    echo "$arg"
}

clavichord_mcp_arg_optional(){
    [[ "$1" =~ \?$ ]]
}

clavichord_mcp_arg_expects_value(){
    [[ "$1" =~ =\??$ ]]
}

clavichord_mcp_arg_is_long_option(){
    [[ "$1" =~ ^--[a-zA-Z0-9_]+ ]]
}

clavichord_mcp_arg_is_short_option(){
    [[ "$1" =~ ^-[a-zA-Z0-9_]+ ]]
}

clavichord_mcp_action_needs_confirmation(){
    local action="$1"

    [ "${action_requires_confirmation[$action]}" == true ] \
        || { [ "${clavichord_mcp_confirm_mutating:-false}" == true ] \
            && [ "${action_mutating[$action]}" == true ]; }
}

clavichord_mcp_tool_schema(){
    local action="$1"
    local args="${action_arguments[$action]}"
    local properties="{}"
    local required="[]"
    local arg name modifier short_names short_name schema

    for arg in $args; do
        if clavichord_mcp_arg_is_long_option "$arg"; then
            name="$(clavichord_mcp_arg_name "$arg")"
            if clavichord_mcp_arg_expects_value "$arg"; then
                schema='{"type":"string"}'
            else
                schema='{"type":"integer","default":0}'
            fi
            properties="$(
                jq -cn \
                    --argjson properties "$properties" \
                    --arg name "$name" \
                    --argjson schema "$schema" \
                    '$properties + {($name): $schema}'
            )"
        elif clavichord_mcp_arg_is_short_option "$arg"; then
            short_names="${arg#-}"
            modifier=""
            if clavichord_mcp_arg_optional "$short_names"; then
                short_names="${short_names%\?}"
                modifier="${modifier}?"
            fi
            if clavichord_mcp_arg_expects_value "$short_names"; then
                short_names="${short_names%=}"
                modifier="${modifier}="
            fi

            local i
            for (( i=0; i<${#short_names}; i++ )); do
                short_name="${short_names:$i:1}"
                if [ "$short_name" == "" ]; then
                    continue
                fi
                if [[ "$modifier" == *"="* ]]; then
                    schema='{"type":"string"}'
                else
                    schema='{"type":"integer","default":0}'
                fi
                properties="$(
                    jq -cn \
                        --argjson properties "$properties" \
                        --arg name "$short_name" \
                        --argjson schema "$schema" \
                        '$properties + {($name): $schema}'
                )"
            done
        else
            name="$(clavichord_mcp_arg_name "$arg")"
            properties="$(
                jq -cn \
                    --argjson properties "$properties" \
                    --arg name "$name" \
                    '$properties + {($name): {"type":"string"}}'
            )"
            if ! clavichord_mcp_arg_optional "$arg"; then
                required="$(
                    jq -cn \
                        --argjson required "$required" \
                        --arg name "$name" \
                        '$required + [$name]'
                )"
            fi
        fi
    done

    if clavichord_mcp_action_needs_confirmation "$action"; then
        properties="$(
            jq -cn \
                --argjson properties "$properties" \
                '$properties + {
                    confirm: {
                        type: "boolean",
                        description: "Must be true to execute this action."
                    }
                }'
        )"
        required="$(
            jq -cn \
                --argjson required "$required" \
                '$required + ["confirm"]'
        )"
    fi

    jq -cn \
        --argjson properties "$properties" \
        --argjson required "$required" \
        '{
            type: "object",
            properties: $properties,
            required: $required,
            additionalProperties: false
        }'
}

clavichord_mcp_tools_list(){
    local tools="[]"
    local action schema read_only destructive

    for action in $(printf "%s\n" "${!available_actions[@]}" | sort); do
        schema="$(clavichord_mcp_tool_schema "$action")"
        read_only="$(clavichord_mcp_json_bool "${action_read_only[$action]}")"
        destructive="$(clavichord_mcp_json_bool "${action_destructive[$action]}")"
        tools="$(
            jq -cn \
                --argjson tools "$tools" \
                --arg name "$action" \
                --arg description "${available_actions[$action]}" \
                --argjson schema "$schema" \
                --argjson readOnlyHint "$read_only" \
                --argjson destructiveHint "$destructive" \
                '$tools + [{
                    name: $name,
                    description: $description,
                    inputSchema: $schema,
                    annotations: {
                        readOnlyHint: $readOnlyHint,
                        destructiveHint: $destructiveHint
                    }
                }]'
        )"
    done

    jq -cn --argjson tools "$tools" '{tools: $tools}'
}

clavichord_mcp_arguments_has(){
    local json="$1"
    local name="$2"

    jq -e --arg name "$name" 'has($name) and .[$name] != null' >/dev/null <<<"$json"
}

clavichord_mcp_arguments_string(){
    local json="$1"
    local name="$2"

    jq -er --arg name "$name" '.[$name] | select(type == "string")' <<<"$json"
}

clavichord_mcp_arguments_integer(){
    local json="$1"
    local name="$2"

    jq -er --arg name "$name" '.[$name] | select(type == "number" and floor == . and . >= 0)' <<<"$json"
}

clavichord_mcp_arguments_boolean(){
    local json="$1"
    local name="$2"

    jq -er --arg name "$name" '.[$name] | select(type == "boolean")' <<<"$json"
}

clavichord_mcp_build_argv(){
    local action="$1"
    local json="$2"
    local args="${action_arguments[$action]}"
    local arg name short_names modifier short_name value count i j

    clavichord_mcp_argv=()
    clavichord_mcp_argument_error=""

    for arg in $args; do
        if clavichord_mcp_arg_is_long_option "$arg"; then
            name="$(clavichord_mcp_arg_name "$arg")"
            if clavichord_mcp_arg_expects_value "$arg"; then
                if clavichord_mcp_arguments_has "$json" "$name"; then
                    if ! value="$(clavichord_mcp_arguments_string "$json" "$name")"; then
                        clavichord_mcp_argument_error="Expected string argument: $name"
                        return 1
                    fi
                    clavichord_mcp_argv+=("--$name" "$value")
                fi
            else
                if clavichord_mcp_arguments_has "$json" "$name"; then
                    if ! count="$(clavichord_mcp_arguments_integer "$json" "$name")"; then
                        clavichord_mcp_argument_error="Expected non-negative integer argument: $name"
                        return 1
                    fi
                    for (( i=0; i<count; i++ )); do
                        clavichord_mcp_argv+=("--$name")
                    done
                fi
            fi
        elif clavichord_mcp_arg_is_short_option "$arg"; then
            short_names="${arg#-}"
            modifier=""
            if clavichord_mcp_arg_optional "$short_names"; then
                short_names="${short_names%\?}"
                modifier="${modifier}?"
            fi
            if clavichord_mcp_arg_expects_value "$short_names"; then
                short_names="${short_names%=}"
                modifier="${modifier}="
            fi

            for (( i=0; i<${#short_names}; i++ )); do
                short_name="${short_names:$i:1}"
                if [ "$short_name" == "" ]; then
                    continue
                fi
                if [[ "$modifier" == *"="* ]]; then
                    if clavichord_mcp_arguments_has "$json" "$short_name"; then
                        if ! value="$(clavichord_mcp_arguments_string "$json" "$short_name")"; then
                            clavichord_mcp_argument_error="Expected string argument: $short_name"
                            return 1
                        fi
                        clavichord_mcp_argv+=("-$short_name" "$value")
                    fi
                else
                    if clavichord_mcp_arguments_has "$json" "$short_name"; then
                        if ! count="$(clavichord_mcp_arguments_integer "$json" "$short_name")"; then
                            clavichord_mcp_argument_error="Expected non-negative integer argument: $short_name"
                            return 1
                        fi
                        for (( j=0; j<count; j++ )); do
                            clavichord_mcp_argv+=("-$short_name")
                        done
                    fi
                fi
            done
        else
            name="$(clavichord_mcp_arg_name "$arg")"
            if clavichord_mcp_arguments_has "$json" "$name"; then
                if ! value="$(clavichord_mcp_arguments_string "$json" "$name")"; then
                    clavichord_mcp_argument_error="Expected string argument: $name"
                    return 1
                fi
                clavichord_mcp_argv+=("$value")
            elif ! clavichord_mcp_arg_optional "$arg"; then
                clavichord_mcp_argument_error="Missing required argument: $name"
                return 1
            fi
        fi
    done
}

clavichord_mcp_tool_result(){
    local text="$1"
    local is_error="${2:-false}"

    jq -cn \
        --arg text "$text" \
        --argjson isError "$(clavichord_mcp_json_bool "$is_error")" \
        '{content: [{type: "text", text: $text}]} + (if $isError then {isError: true} else {} end)'
}

clavichord_mcp_call_tool(){
    local request="$1"
    local name arguments_json confirm
    local stdout_file="" stderr_file="" stdout_text stderr_text output exit_code result

    clavichord_mcp_call_tool_cleanup(){
        if [ "$stdout_file" != "" ]; then
            rm -f "$stdout_file"
        fi
        if [ "$stderr_file" != "" ]; then
            rm -f "$stderr_file"
        fi
    }
    trap clavichord_mcp_call_tool_cleanup RETURN

    name="$(jq -er '.params.name | select(type == "string")' <<<"$request")" || {
        clavichord_mcp_tool_result "Missing tool name" true
        return
    }

    if [ "${available_actions[$name]+exist}" != "exist" ]; then
        clavichord_mcp_tool_result "Unknown tool: $name" true
        return
    fi

    arguments_json="$(jq -c '.params.arguments // {}' <<<"$request")"
    if ! jq -e 'type == "object"' >/dev/null <<<"$arguments_json"; then
        clavichord_mcp_tool_result "Tool arguments must be an object" true
        return
    fi

    if [ "${clavichord_mcp_read_only:-false}" == true ] \
    && [ "${action_read_only[$name]}" != true ]; then
        clavichord_mcp_tool_result "Refusing to run '$name' because MCP read-only mode is active." true
        return
    fi

    if [ "${clavichord_mcp_deny_destructive:-false}" == true ] \
    && [ "${action_destructive[$name]}" == true ]; then
        clavichord_mcp_tool_result "Refusing to run '$name' because destructive actions are denied." true
        return
    fi

    if clavichord_mcp_action_needs_confirmation "$name"; then
        confirm="$(clavichord_mcp_arguments_boolean "$arguments_json" confirm 2>/dev/null || echo false)"
        if [ "$confirm" != true ]; then
            clavichord_mcp_tool_result "Refusing to run '$name' without confirm=true."
            return
        fi
    fi

    if ! clavichord_mcp_build_argv "$name" "$arguments_json"; then
        clavichord_mcp_tool_result "$clavichord_mcp_argument_error" true
        return
    fi

    stdout_file="$(mktemp)" || {
        clavichord_mcp_tool_result "Failed to create temporary stdout file." true
        return
    }
    stderr_file="$(mktemp)" || {
        rm -f "$stdout_file"
        clavichord_mcp_tool_result "Failed to create temporary stderr file." true
        return
    }
    (
        h=0
        parse_arguments "${action_arguments[$name]}" "${clavichord_mcp_argv[@]}"
        if [ "${h:=0}" -gt 0 ]; then
            get_help "$name"
            exit 1
        fi
        "$name" "${arguments[@]}"
    ) >"$stdout_file" 2>"$stderr_file"
    exit_code=$?

    stdout_text="$(<"$stdout_file")"
    stderr_text="$(<"$stderr_file")"

    output="$stdout_text"
    if [ "$stderr_text" != "" ]; then
        if [ "$output" != "" ]; then
            output="$output
$stderr_text"
        else
            output="$stderr_text"
        fi
    fi

    if [ "$exit_code" -eq 0 ]; then
        result="$(clavichord_mcp_tool_result "$output")"
    else
        result="$(clavichord_mcp_tool_result "$output" true)"
    fi
    echo "$result"
}

clavichord_mcp_send_response(){
    local id="$1"
    local result="$2"

    jq -cn \
        --argjson id "$id" \
        --argjson result "$result" \
        '{jsonrpc: "2.0", id: $id, result: $result}'
}

clavichord_mcp_send_error(){
    local id="$1"
    local code="$2"
    local message="$3"

    jq -cn \
        --argjson id "$id" \
        --argjson code "$code" \
        --arg message "$message" \
        '{jsonrpc: "2.0", id: $id, error: {code: $code, message: $message}}'
}

clavichord_mcp_initialize_result(){
    local instructions="${mcp_instructions:-}"

    if [ "$instructions" != "" ]; then
        jq -cn \
            --arg name "$program_name" \
            --arg instructions "$instructions" \
            '{
                protocolVersion: "2024-11-05",
                capabilities: {
                    tools: {}
                },
                serverInfo: {
                    name: $name,
                    version: "0.1.0"
                },
                instructions: $instructions
            }'
    else
        jq -cn \
            --arg name "$program_name" \
            '{
                protocolVersion: "2024-11-05",
                capabilities: {
                    tools: {}
                },
                serverInfo: {
                    name: $name,
                    version: "0.1.0"
                }
            }'
    fi
}

clavichord_mcp_loop(){
    local line id method result

    while IFS= read -r line; do
        if [ "$line" == "" ]; then
            continue
        fi

        if ! jq -e . >/dev/null 2>&1 <<<"$line"; then
            clavichord_mcp_send_error null -32700 "Parse error"
            continue
        fi

        id="$(jq -c '.id // null' <<<"$line")"
        method="$(jq -r '.method // empty' <<<"$line")"

        case "$method" in
            initialize)
                result="$(clavichord_mcp_initialize_result)"
                clavichord_mcp_send_response "$id" "$result"
                ;;
            notifications/initialized)
                ;;
            tools/list)
                result="$(clavichord_mcp_tools_list)"
                clavichord_mcp_send_response "$id" "$result"
                ;;
            tools/call)
                result="$(clavichord_mcp_call_tool "$line")"
                clavichord_mcp_send_response "$id" "$result"
                ;;
            *)
                if [ "$id" != null ]; then
                    clavichord_mcp_send_error "$id" -32601 "Method not found"
                fi
                ;;
        esac
    done
}
