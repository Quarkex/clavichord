if [ "$program_path"    == "" ] \
|| [ "$program_name"    == "" ] \
|| [ "$program_bin_dir" == "" ] \
|| [ "$program_lib_dir" == "" ] \
; then
    program_path=`realpath $0`
    program_name=`basename "$path"`
    program_bin_dir=`dirname $path`
    program_lib_dir="${bin_dir/\/bin/\/lib/}"
fi
play() {(

####### Begin of scripting clockworks #########################################

    program_name="$program_name"
    program_arguments=(action_name)

    declare -a arguments
    parse_arguments(){

        function_arguments="$1"
        shift

        # Empty the argument stack, but do not unset variable
        while [ "${#arguments[@]}" -gt 0 ] ; do
            arguments=("${arguments[@]:1}")
        done

        arg_expects_value(){(
            if [[ "$1" =~ [a-zA-Z0-9_]+[?]?=[?]?$ ]]; then
                echo "${1}" | tr -d '='
            else
                echo ""
            fi
        )}
        arg_is_optional(){(
            if [[ "$1" =~ [a-zA-Z0-9_]+[=]?\?[=]?$ ]]; then
                echo ${1#--} | tr -d '?'
            else
                echo ""
            fi
        )}
        arg_is_flag(){(
            if [ ! "`arg_is_long_option $1`" == "" ]; then
                echo ""
            else
                if [[ "$1" =~ ^-[a-zA-Z0-9_]+ ]]; then
                    local args="${1#-}"
                    local flags=""
                    for (( i=0; i<${#key}; i++ )); do
                        if [ "${args:$i:1}" == "?" ]; then
                            flags="$flags${args:$i:1}"
                        else
                            flags="$flags ${args:$i:1}"
                        fi
                    done
                    echo "$flags"
                else
                    echo ""
                fi
            fi
        )}
        arg_is_long_option(){(
            [[ "$1" =~ ^--[a-zA-Z0-9_]+ ]] && echo ${1#--} || echo ""
        )}
        arg_is_value(){(
            if [ "`arg_is_long_option "$1"`" == ""  ] \
            && [ "`arg_is_flag        "$1"`" == ""  ] \
            ; then
                echo "$1"
            else
                echo ""
            fi
        )}
        arg_name(){(
            output="$1"
            if [ "`arg_is_value "$output"`" == "" ]; then
                output="${output##-}"
                output="${output##-}"
                [ ! "`arg_is_optional "$output"`" == "" ] \
                    && output="`arg_is_optional "$output"`"
                [ ! "`arg_expects_value "$output"`" == "" ] \
                    && output="`arg_expects_value "$output"`"
            fi
            echo "$output"
        )}

        arg_pending_for_val=""
        declare -a possible_arguments
        declare -a possible_options
        declare -a possible_flags
        declare -A values
        required_values=0
        supplied_values=0

        declare -a args
        for arg in "$@"; do args+=("$arg"); done

        for arg in $function_arguments; do
            if [ ! "`arg_is_value "$arg"`" == "" ]; then
                possible_arguments+=("$arg")
                [ "`arg_is_optional "$arg"`" == "" ] && \
                    required_values=$(( 1 + ${required_values:-0} ))
            else
                if [ `arg_is_long_option "$arg"` ]; then
                    arg="`arg_is_long_option "$arg"`"
                    possible_options+=("$arg")
                else
                    for flag in `arg_is_flag "$arg"`; do
                        possible_flags+=("$flag")
                    done
                fi

            fi
        done

        ignore_current_argument(){
            arguments+=( "${args[0]}" )
            args=("${args[@]:1}")
        }
        assign_arg_to_pending_value(){
            values+=([$arg_pending_for_val]="${args[0]}")
            args=("${args[@]:1}")
            arg_pending_for_val=""
        }
        assign_arg_to_possible_argument(){
            values+=([$possible_arguments]="${args[0]}")
            possible_arguments=("${possible_arguments[@]:1}")
            args=("${args[@]:1}")
        }
        assign_optional_arg_to_possible_argument(){
            possible_argument=`arg_is_optional "$possible_arguments"`
            if [[ ! ${#args[@]} -gt 0 ]]; then
                values+=([$possible_argument]="")
            else
                values+=([$possible_argument]="${args[0]}")
                args=("${args[@]:1}")
            fi
            possible_arguments=("${possible_arguments[@]:1}")
        }
        assign_arg_to_long_option(){
            arg="`arg_is_long_option "${args[0]}"`"
            match_opt=""
            match_opt_expects_value=false
            for opt in "${possible_options[@]}"; do
                if [ `arg_is_optional "$opt"` ]; then
                    opt=`arg_is_optional "$opt"`
                fi
                if [ `arg_expects_value "$opt"` ]; then
                    opt=`arg_expects_value "$opt"`
                    expects_value=true
                else
                    expects_value=false
                fi
                opt="${opt//\?/}"
                opt="${opt//=/}"
                if [ "$arg" == "$opt" ]; then
                    match_opt="$opt"
                    match_opt_expects_value=$expects_value
                fi
            done

            if [ ! "$match_opt" ]; then
                arguments+=( ${args[0]} )
            else
                if [ $match_opt_expects_value == true ]; then
                    arg_pending_for_val="$match_opt"
                else
                    values+=( [$match_opt]=$(( ${values[$match_opt]:-0} + 1 )) )
                fi
            fi
            args=("${args[@]:1}")
        }
        assign_arg_to_flag(){
            arg="`arg_is_flag "${args[0]}"`"
            for flag in $arg; do
                match_flag=""
                match_flag_expects_value=false
                for possible_flag in "${possible_flags[@]}"; do
                    if [ `arg_is_optional "$possible_flag"` ]; then
                        possible_flag=`arg_is_optional "$possible_flag"`
                    fi
                    if [ `arg_expects_value "$possible_flag"` ]; then
                        possible_flag=`arg_expects_value "$possible_flag"`
                        expects_value=true
                    else
                        expects_value=false
                    fi
                    possible_flag="${possible_flag//\?/}"
                    possible_flag="${possible_flag//=/}"
                    if [ "$flag" == "$possible_flag" ]; then
                        match_flag="$flag"
                        match_flag_expects_value=$expects_value
                    fi
                done

                if [ ! "$match_flag" ]; then
                    arguments+=( "-$flag" )
                else
                    if [ $match_flag_expects_value == true ]; then
                        arg_pending_for_val="$match_flag"
                    else
                        values+=( [$match_flag]=$(( ${values[$match_flag]:-0} + 1 )) )
                    fi
                fi
            done
            args=("${args[@]:1}")
        }

        while [ "${#args[@]}" -gt 0 ] ; do
            arg="${args[0]}"

            if [ ! "${#possible_arguments[@]}" -gt 0 ]; then

                dont_ignore_this_arg=false

                if [ ! "`arg_is_value "$arg"`" == "" ]; then
                    if [ "$arg_pending_for_val" ]; then
                        assign_arg_to_pending_value
                        continue
                    fi
                fi

                if [ ! "`arg_is_long_option "$arg"`" == "" ]; then
                    opt="`arg_is_long_option "$arg"`"
                    opt="${opt//\?/}"; opt="${opt//=/}"
                    for possible_option in "${possible_options[@]}"; do
                        possible_option="${possible_option//\?/}"
                        possible_option="${possible_option//=/}"
                        if [ "${opt}" == "$possible_option" ]; then
                            dont_ignore_this_arg=true
                            assign_arg_to_long_option
                            break;
                        fi
                    done
                    [ $dont_ignore_this_arg == true ] && continue
                fi

                if [ ! "`arg_is_flag "$arg"`" == "" ]; then
                    flg="`arg_is_flag "$arg"`"
                    flg="${flg//\?/}"; flg="${flg//=/}"
                    flg="`echo ${flg//\?/}`"
                    for possible_flag in "${possible_flags[@]}"; do
                        possible_flag="${possible_flag//\?/}"
                        possible_flag="${possible_flag//=/}"
                        if [ "${flg}" == "$possible_flag" ]; then
                            dont_ignore_this_arg=true
                            assign_arg_to_flag
                            break;
                        fi
                    done
                    [ $dont_ignore_this_arg == true ] && continue
                fi

                if [ $dont_ignore_this_arg == false ]; then
                    ignore_current_argument
                fi

            else
                possible_argument="$possible_arguments"
                if [ "`arg_is_long_option "$arg"`" == "" ] \
                && [ "`arg_is_flag "$arg"`" == "" ] \
                ; then
                    if [ "$arg_pending_for_val" ]; then
                        assign_arg_to_pending_value
                        continue
                    fi

                    supplied_values=$(( 1 + ${supplied_values:-0} ))
                    if [ ! "`arg_is_optional "$possible_argument"`" == "" ]; then
                        assign_optional_arg_to_possible_argument
                    else
                        assign_arg_to_possible_argument
                    fi
                else
                    if [ ! "`arg_is_long_option "$arg"`" == "" ]; then
                        assign_arg_to_long_option
                    else
                        assign_arg_to_flag
                    fi
                fi
            fi
        done

        for key in ${!values[@]}; do
            eval "${key}=${values[$key]}";
        done

        if [ ! $supplied_values -ge $required_values ]; then
            [ ! ${h:-0} -ge 0 ] && echo "ERROR: wrong number of arguments"
            h=$(( 1 + ${h:-0} ))
        fi
    }

    get_config_value(){(
        variable_name="$1"
        default_value="$2"
        regex_key="[[:space:]]*$variable_name[[:space:]]*"
        regex_value='[[:space:]]*"\?\([^"]*\)"\?[[:space:]]*'
        regex="^$regex_key=$regex_value\$"

        value="$default_value"
        for conf_file in \
            "/etc/$program_name/config" \
            "/etc/$program_name.conf" \
            "$HOME/.$program_name/config" \
            "$HOME/.$program_name.conf" \
        ; do
            if [[ -f "$conf_file" ]]; then
                line="$(
                    egrep "^$regex_key=" "$conf_file" || echo "" )"
                if [ ! "$line" == "" ]; then
                    value="$( echo "$line" \
                    | sed "s/$regex/\1/" \
                    | head -n 1 )"
                fi
            fi
        done
        echo "$value"
    )}

    if [[ -f "$program_lib_dir/${program_name}/config.sh" ]]; then
        source "$program_lib_dir/${program_name}/config.sh"
    fi

    declare -A help_messages
    declare -A available_actions
    declare -A action_arguments

    set_action(){
        action="$1"
        shift;
        args="$1"
        shift;
        one_liner="$1"
        shift;
        body=""
        for line in "$@"; do
            [ "$body" == "" ] && body="${line}" || body="${body}\n${line}";
        done

        available_actions["${action}"]="$one_liner"
        action_arguments["${action}"]="$args"
        options_with_arguments+=(
            $(echo $args | tr " " "\n" | grep '=' | tr -d "=" | tr -d "?" )
        )
        set_help "$program_name/$action" "$body"
    }
    set_help(){
        key="$1"
        shift;
        body=""
        for line in "$@"; do
            [ "$body" == "" ] && body="${line}" || body="${body}\n${line}";
        done

        help_messages["$key"]="$body"
    }
    get_help(){(
        show_help \
            "$program_name" \
            "$action_name" \
            "$project_name" \
            "$instance_name" \
            $@; return $?
    )}
    show_help(){(
        target=default
        key=""
        for argument in $@; do
            [[ "$key" == "" ]] && key="$argument" || key="$key/$argument"

            if [ "${help_messages[$key]+exist}" ]; then
                target="${key}"
            else
                if [ -d "$sources_folder/$argument" ]; then
                    if [ "${help_messages["${key}/project"]+exist}" ]; then
                        target="${key}/project"
                    fi
                fi
            fi
        done
        message="${help_messages["$target"]}"
        while [[ "$message" =~ (.*)%=(.*)%(.*) ]]; do
            pre="${BASH_REMATCH[1]}"
            match="${BASH_REMATCH[2]}"
            post="${BASH_REMATCH[3]}"
            message="$pre$(eval ${match})$post"
        done
        while [[ "$message" =~ .*%([a-zA-Z0-9_]+)%.* ]]; do
            match="${BASH_REMATCH[1]}"
            value="${!match}"
            message="$(echo "$message" | sed "s/%$match%/${value:-<$match>}/g")"
        done
        echo -e "$message"
        return -1
    )}
    get_help_variable_list(){(
        if [[ -f "$sources_folder/$project_name/.env" ]]; then
            echo "$(
                sed \
                    -e 's/^[\s]*//g' \
                    -e 's/^\(.*\)=/        --\L\1=/g' \
                    -e 's/=\(.*\)$/ [\1]/g' \
                    -e 's/ \[\]/ "<value>"/g' \
                    -e 's/\(--compose_project_name \)\[.*\]/\1['"$project_name-${instance_name:-<instance_name>}"']/g' \
                    -e 's/$/ \\\\/g' \
                    -e '$ s/ \\\\//g' \
                    "$sources_folder/$project_name/.env"
            )"
        else
            echo "        --<variable> <value> \\"
            echo "        --<variable> <value> \\"
            echo "        --<variable> <value> \\"
            echo "        ..."
            echo "        --<variable> <value> "
        fi
    )}
    get_folder_size(){(
        folder="$1"
        du -csh "$folder" \
        | tail -n 1 \
        | sed 's/[ ]*total//g'
    )}

  ########
 # Main #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
########

    set_help "$program_name" \
    "Usage:" \
    "  $program_name <action> [arguments]" \
    "" \
    "Commands:" \
    "%=$program_name actions -d%" \
    ""

    main(){(
        if [ "$action_name" == "" ]; then
            get_help $@; return $?
        else
            if [ "${available_actions[$action_name]+exist}" == "exist" ]; then
                parse_arguments "${action_arguments[$action_name]}" $@
                if [ ${h:=0} -gt 0 ]; then
                    get_help $@; return $?
                else
                    $action_name ${arguments[@]}
                fi
            else
                echo "ERROR: unknown action “$action_name”"
                get_help $@; return $?
            fi
        fi
    )}

  ###########
 # Actions #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#
###########

    set_action "actions" "-d"\
    "List availible actions in this program" \
    "Usage:" \
    "  %program_name% %action_name%" \
    "" \
    "Or if you want to list actions with a short description:" \
    "  %program_name% %action_name% -d" \
    "" \
    ""

    actions(){(
        [[ "$d" -gt 0 ]] && show_description=true;

        if [[ $show_description == true ]]; then
            max_length=0
            for action in ${!available_actions[@]}; do
                if [ ${#action} -gt $max_length ]; then
                    max_length=${#action}
                fi
            done

            action_column_width=$(( $max_length + 4 ))
            cols="$(tput cols 2>/dev/null || echo 80)"
            description_column_width=$(( $cols - $action_column_width - 2 ))
            padding="$(printf '%*s' $action_column_width "")"

            for action in ${!available_actions[@]}; do
                head="${action}${padding::-${#action}}"
                line="$(
                    echo "${available_actions[${action}]}" \
                    | fmt -w $description_column_width
                    )"

                echo "${line}" | sed \
                    -e "1 s/^/  ${head::-2}/g" \
                    -e "1!s/^/  $padding/g"
            done
        else
            for action in ${!available_actions[@]}; do
                echo ${action}
            done
        fi

        return 0

    )}
 #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#

     if [ -d "$action_definitions_folder" ]; then
        for action in "$action_definitions_folder"/*.sh; do
            source "$action"
        done
     fi

# Execute main function
# and return the exit code
parse_arguments "action_name -h?" $@
main "${arguments[@]}"; return $?)}
