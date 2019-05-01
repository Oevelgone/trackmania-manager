#!/bin/bash
# shellcheck disable=

###############################################################################
#Set of common functions used in most of my scripts
#Copyright (C) 2018 Navarra Manuel
#Contact : admin[at]icp[dot]ovh

#This program is free software: you can redistribute it and/or modify
#it under the terms of the GNU General Public License as published by
#the Free Software Foundation, either version 3 of the License, or
#(at your option) any later version.

#This program is distributed in the hope that it will be useful,
#but WITHOUT ANY WARRANTY; without even the implied warranty of
#MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#GNU General Public License for more details.

#You should have received a copy of the GNU General Public License
#along with this program.  If not, see <https://www.gnu.org/licenses/>.
###############################################################################

#Variables
declare LINE_CLEAR='\e[2K\r'
declare LINE_BACK='\e[1A\e[2K\r'
# COLORS {{{
Bold=$(tput bold)
Underline=$(tput sgr 0 1)
Reset=$(tput sgr0)
# Regular Colors
Red=$(tput setaf 1)
Green=$(tput setaf 2)
Yellow=$(tput setaf 3)
Blue=$(tput setaf 4)
Purple=$(tput setaf 5)
Cyan=$(tput setaf 6)
White=$(tput setaf 7)
# Bold
BRed=${Bold}${Red}
BGreen=${Bold}${Green}
BYellow=${Bold}${Yellow}
BBlue=${Bold}${Blue}
BPurple=${Bold}${Purple}
BCyan=${Bold}${Cyan}
BWhite=${Bold}${White}
#}}}
#Basic functions {{{
function ui_error() { #Parameter -- 1:(str) error_message {{{
printf '%bEncoutered fatal error in function "%s" from "%s" with error message : "%s"' "${LINE_CLEAR}" "${FUNCNAME[1]}" \
"${BASH_SOURCE[0]}" "${1:-No message provided}"
} #}}}
function contains_element() { #{{{
for element in "${@:2}"; do [[ "${element}" == "${1}" ]] && break; done;
} #}}}
function copy_associative_array() { # {{{
for key in $(eval "echo \${!${1:?$(ui_error '$1 not defined')}[@]}"); do
   eval "${2:?$(ui_error '$2 not defined')}[${key}]=\"$(eval "echo \${${1:?$(ui_error '$1 not defined')}[${key}]}")\""
done
} #}}}
function array_index() { #Parameters -- 1:(str) value, 3:(array) {{{
local i=0
for value in "${@:2}"; do
    if [[ "${1:?$(ui_error '$1 not defined')}" == "${value}" ]]; then
        printf '%d' "${i}"
    fi
    ((i++))
done
} #}}}
function copy_var() { # Parameters -- 1:(str) original_var_name, 2:(str) new_var_name
eval "$(declare -p ${1:?$(ui_error 'Missing arg1')} | sed "s/${1}=/ -g ${2:?$(ui_error 'Missing arg2')}=/g")"
}
#}}}
#Print functions, based on the functions from aui by helmuthdu {{{
function pause_key() { #{{{
    read -sn 1 -p "
Press any key to continue..."
} #}}}
function print_line() { #{{{
printf "%$(tput cols)s\n"|tr ' ' '-'
} #}}}
function print_title() { #{{{
clear
print_line
echo -e "# ${Bold}$1${Reset}"
print_line
echo ""

} #}}}
function print_info() { #{{{
#Console width number
T_COLS=`tput cols`
echo -e "${Bold}$1${Reset}\n" | fold -sw $(( $T_COLS - 18  )) | sed 's/^/\t/'

} #}}}
function print_menu() { #Parameters -- 1:(str)STRUCTURE_ARRAY_NAME, 2:(str) function_to_call {{{
local -r ARRAYNAME="${1:-MENU_STRUCTURE}"
local -ag menu_list=()
local -ag menu_keys=()
declare -Ag _menu_structure=()

copy_associative_array "${ARRAYNAME:?$(ui_error 'No array passed as _arg1 or MENU_STRUCTURE not defined')}" _menu_structure

for key in ${_menu_structure["list"]:?$(ui_error "${ARRAYNAME}[list] is not defined")}; do
    menu_keys+=("${key}")
    menu_list+=("${_menu_structure["${key},title"]:-${key}}")
    #menu_list+=("${_menu_structure["${key},title"]:?$(ui_error "${ARRAYNAME}[${key},title] is not defined")}")
done

PS3="
Select an option [1-${#menu_keys[@]}] : "

select entry in "${menu_list[@]}"; do
if contains_element "${entry}" "${menu_list[@]}"; then
    ${2:?$(ui_error 'No function_name passed as _arg2')} "${entry}"
    break
else
    echo "Invalid choice"
fi
done
PS3="#?"
} #}}}
function print_ui() {
local -ag arg_array
copy_var ${1:?$(ui_error 'No array name passed as _arg1')} arg_array
#eval arg_array=\( \${${1:? ui_error 'No array name passed as _arg1'}[@]} \)
local arg1 arg2
local -a args

for entry in "${arg_array[@]}"; do
    arg1="$(cut -d';' -f1 <<<"${entry}")"
    arg2="$(cut -d';' -f2 <<<"${entry}")"
    args=($(cut -d';' -f3 <<<"${entry}"))
    if [ "$(type -t "print_${arg1}")" == "function" ]; then
        "print_${arg1}" "${arg2}" ${args[@]}
    elif [ "${arg1}" == "cmd" ]; then
        "${arg2}" ${args[@]}
    else
        ui_error "Runtime error"
    fi
done
}
#}}}
