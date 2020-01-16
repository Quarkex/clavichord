#!/bin/bash
_clavichord_completions()
{
    if [ ! "${#COMP_WORDS[@]}" -gt 1 ]; then
        return
    else
        last_word="${COMP_WORDS[$(( ${#COMP_WORDS[@]} - 1 ))]}"
        arguments="$( clavichord actions )"
        if [ ! "${#COMP_WORDS[@]}" -eq 2 ]; then
            case "${#COMP_WORDS[@]}" in
                *) arguments="";;
            esac
            action="${COMP_WORDS[1]}"
            case "$action" in
                #action_a)
                #
                #    ...logic...
                #
                #    arguments="...$arguments..."
                #    ;;
                #action_b)
                #
                #    ...logic...
                #
                #    arguments="...$arguments..."
                #    ;;
                #*)
                #
                #    ...logic...
                #
                #    arguments="...$arguments..."
                #    ;;
            esac

        fi
        [ "$arguments" == "" ] && return || COMPREPLY=($(compgen -W "$arguments" "$last_word"))
    fi
}
complete -o nospace -F _clavichord_completions clavichord
