Clavichord
==========

The clavichord is a European stringed rectangular keyboard instrument that was
used largely in the Late Middle Ages, through the Renaissance, Baroque and
Classical eras. Historically, it was mostly used as a practice instrument and
as an aid to composition, not being loud enough for larger performances.

This is a small framework to ease the composition of complex scripts, with
various actions, help menus and autocompletion.

Usage
-----

This expects to coexists with other libraries inside a “lib” folder, linking
the “clavichord” executable to a “bin” folder with another name.

This is an example of a project using clavichord:

    project
     |->bin/
     |   |->project* <-------------| S
     |                             | i
     |->project.conf               | m
     |->install_autocompletion.sh  | l
     |->lib/                       | i
         |->clavichord/            | n
         |   |->clavichord* <------| k
         |   |->completion.bash
         |   |->config.sh
         |   |->play.sh
         |
         |->project/
             |->actions.d/
             |   |-> action_a.sh
             |   |-> action_b.sh
             |   |-> action_c.sh
             |   |-> ...
             |
             |->completion.bash
             |->config.sh

The name of the link inside the bin folder is used to reference the
actions and you may have any number of them, each one with a different set
of actions, config options, etc.

Each “config.sh” file defines configurable options for a project, which
then can be used inside the “.conf” files. These files are simple
“KEY=value” files.

Clavichord projects will look for config files in this order:

* /etc/project/config
* /etc/project.conf
* ~/.project/config
* ~/.project.conf

Each file override the previous one, allowing to have personal
configurations per user and system-wide.

Inside the clavichord folder you will find a “comletion,bash” file you can
use as reference to write custom bash completion scripts. Once writen,
link them inside “/etc/bash_completion.d/” to be sourced automatically.

Each project expects an “actions.d” folder that will contain a file per action.

Actions are nothing more than functions sourced inside “play.sh”. To make
clavichord aware of this function as an action, you need to use the
“set_action” function like this:

```
set_action <action_name> <action_arguments> \
    <one_line_action_description>           \
    <long_description_line_1>               \
    <long_description_line_2>               \
    <long_description_line_3>               \
    .                                       \
    .                                       \
    .                                       \
    <long_description_line_n>               \
```

If you need to use a variable inside the long description of an action,
use `%variable_name%`. It will be replaced with `<variable_name>` if undefined,
and if you need to use the result of a subshell, user `%= command [args]%`.
This variables and functions are executed after the program has fully loaded
instead of when the action is defined.

Possible arguments are parsed from a single string, with arguments
separated by spaces. Arguments can be required, optional, and flags or
long options with and without values. E.G:

`required_argument optional_argument? -f -v= --long_option --option_with_value=`

This line defines:

* a `required_argument` accesible with `$required_argument`
* an `optional_argument?` accesible with `$optional_argument`
* a `f` flag accesible with `$f`
* a `v` flag which expect a value accesible with `$v`
* a `--long_option` accesible with `$f`
* a `--option_with_value=` accesible with `$option_with_value`

Flags and options are always optional, and if required should be tested
inside the action function.

Those flags and functions which do not accept a value are not booleans,
but integers, and you may call them any number of times, increasing them
by one each time.

If less arguments than the required are passed to the project when running it,
an error is thrown with a proper message warning about it, and the help is
displayed.

You may pass any number of extra arguments, which will be passed to the
action function to be used as seem fit or ignored. Common usage of this is
to call arbitrary programs inside the actions and pass the arguments to
them.

