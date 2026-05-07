action_definitions_folder="$(
    get_config_value \
        "ACTION_DEFINITIONS_FOLDER" \
        "$program_lib_dir/${program_name}/actions.d"
)"

mcp_instructions="$(
    get_config_value \
        "MCP_INSTRUCTIONS" \
        ""
)"
