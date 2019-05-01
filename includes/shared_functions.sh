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

declare -i VERBOSE_LEVEL=0
declare -i LOG_LEVEL=-1
declare -g REPLY # used for read_input_multichoice
declare LINE_CLEAR='\e[2K\r'
declare LINE_BACK='\e[1A\e[2K\r'
# Basic Functions {{{
function bin_check() { # Parameters -- 1:(str)"list of bin to check" {{{
local missing_bin
for bin in ${required_bin}; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
        printf '"%s" not found, please install it.\n' "${bin}"
        missing_bin=true
    fi
done
if [ "${missing_bin}" ]; then
    exit 1
fi
} #}}}
function check_file() { #Parameters -- 1:(str)"path_to_file" *:FLAGS{IS_DIR,R,W,X} {{{
local CHECK_IS_DIR=false
local CHECK_R=false
local CHECK_W=false
local CHECK_X=false

#echo $@
local file="${1}"; shift

for flag in ${@}; do
    #echo $flag
    local var_name="CHECK_$flag"
    #echo "${!var_name}"
    if [ -z ${!var_name+x} ]; then
        printf 'Flag %s is invalid. FATAL ERROR\n' ${flag}
        exit 1
    else
        eval "${var_name}=true"
    fi
done

if [ ! -e "${file}" ]; then
    return 1
fi

if [ "${CHECK_IS_DIR}" == "true" ] && [ ! -d "${file}" ]; then
    return 2
fi
if [ "${CHECK_R}" == "true" ] && [ ! -r "${file}" ]; then
    return 3
fi
if [ "${CHECK_W}" == "true" ] && [ ! -w "${file}" ]; then
    return 4
fi
if [ "${CHECK_X}" == "true" ] && [ ! -x "${file}" ]; then
    return 5
fi
return 0
} #}}}
function contains_element() { #{{{
for element in "${@:2}"; do [[ "${element}" == "${1}" ]] && break; done;
} #}}}
function copy_associative_array() { # {{{
for key in $(eval "echo \${!${1:?ui_error '$1 not defined'}[@]}"); do
   eval "${2:?ui_error '$2 not defined'}[${key}]=$(eval "echo \${${1:?ui_error '$1 not defined'}[${key}]}")"
done
} #}}}
function get_opt_verbose() { #Parameters -- 1:(str)"short_options" 2:(str)"long_options" {{{
local short_options="${1}"
local long_options="${2// /,}"
shift 2
ARGS=$(getopt -o v:${short_options} -l "verbose:,${long_options}" -- "${@}") || exit 1 # Opt followed by ":" if a parameter is needed

eval set -- "${ARGS}";

while true; do
    case ${1} in
        -v|--verbose)
            [[ -n "${2}" ]] && {
            VERBOSE_LEVEL="${2}"
            shift 2
        } || exit 2;;
    --)
        shift
        break;;
    *)
        shift;;
esac
done

[[ "${VERBOSE_LEVEL}" -eq -1 ]] && { VERBOSE_LEVEL=256; set -x; }

#eval set -- ${ARGS};

#while true; do
#case ${1} in
#-v|--verbose)
    #shift 2;;
#-h|--help)
    #usage ""
    #shift;;
#--opt)
    #[[ -n "${2}" ]] && {
    #OPT="${2}"
    #shift 2
    #} || exit 2;;
#--)
    #shift
    #break;;
#*)
    #usage
    #;;
#esac
#done
} #}}}
function package_check() { # Parameters -- 1:(str)"list of package to check"{{{
command -v pacman || { printf 'package_check can work only on archlinux based os for now\nThe following packages are required (find you equivalents) : ' "${1}"; return 0; }
local missing_package
for package in ${1}; do
    if ! pacman -Qi "${package}" >/dev/null 2>&1; then
        printf 'Package "%s" is not installed, this package is required.\n' "${package}"
        missing_package=true
    fi
done
if [ "${missing_package}" ]; then
    exit 1
fi
} #}}}
function read_input_multichoice() { # Parameters -- 1:(str)"Text to display" "key list" {{{
local read_text="${1:?Missing param to function read_input_multichoice}"
local key_list="${2:?Missing param to function read_input_multichoice}"
REPLY=""

read -r -n 1 -p "${read_text}" REPLY

if match_in_list "${REPLY}" "${key_list}" true; then
    return_value="${REPLY,,}" # Return action key in lowercase
else
    printf '\e[2K\r'
    read_input_multichoice "$@"
fi
printf '\e[2K\r'
} #}}}
function usage() { #Parameters -- 1:(str)"Usage message" {{{
printf '%s usage : %s\n%s\n' "$(basename $0)" "${1:-}" "${USAGE_MESSAGE}"
exit 1
} #}}}
#match_in_list - Parameters -- 1:(str) str_to_search 2:(str)"List of str" 3:(bool)case_insensitive? #{{{
#This function check if the first parameter exist in a list of strings (second parameter)
#if third parameter is set (true) then the comparaison will be case insensitive
#Return 0 if matching was successfull or 1 if it failed.
function match_in_list() {
local first_param="${1:?Missing param to function match_in_list}"
local second_param="${2:?Missing param to function match_in_list}"
local char
if [ "${3}" ]; then
    char=${first_param,,}
else
    char=${first_param}
fi
for i in ${second_param}; do
    if [[ "${char}" == "${i}" ]]; then
        return 0
    fi
done
return 1
} #}}}
#}}}
#Log Handler {{{
LDEFAULT() { LOG_LEVEL=0; }
LVERBOSE() { LOG_LEVEL=1; }
LDEBUG() { LOG_LEVEL=255; }
function LOG() { #Parameters -- 1:LOG_LEVEL 2:(str)"LOG Message" {{{
local message=""
${1} > /dev/null 2>&1
if [ "${LOG_LEVEL}" == -1 ]; then
    printf 'LOG called with invalid LOG_LEVEL\n'
    exit 1
fi
if [ "${LOG_LEVEL}" -ge 255 ]; then
    message="DEBUG -- "
fi
message+=${2:-LOG called without message}
[[ "${VERBOSE_LEVEL:?VERBOSE_LEVEL not defined}" -ge ${LOG_LEVEL}  ]] && printf '%b\n' "${message}"
message=""
LOG_LEVEL=-1
} #}}}
#}}}
#Exit functions {{{
function exit_handler() { #Parameters -- 1:(int)"exit_value" 2:(str)"EXIT Array name"{{{
#LOG LDEBUG "
#called exit_handler $(echo $@)"
local -i exit_value="${1:?Missing (int)exit_value in function exit_handler :1}"
local _arg2="${2:-EXIT_MESSAGES}"[@]
shift 2
local -a exit_messages=("${!_arg2:?"No exit messages registered (Fill EXIT_MESSAGES or send an array name as second parameter to exit_handler)"}")

LOG LDEFAULT "$(printf '%bEncountered fatal error in function path \"%s" from file "%s" with message : "%s"' \
"${LINE_CLEAR}" "${FUNCNAME[*]#exit_handler}" "${BASH_SOURCE[0]}" \
"$(printf "$(eval echo ${exit_messages["${exit_value}"]:?"No exit message for code ${exit_value}"})" $@)"
)"
exit "${exit_value}"
#LOG LDEFAULT "$(printf "${LINE_CLEAR}Encountered fatal error in function path \"${FUNCNAME[*]#exit_handler}\"
#File : ${BASH_SOURCE[0]}\\\n\
#Message :\\\n\
#$(eval echo ${exit_messages["${exit_value}"]:?"No exit message for code ${exit_value}"})" $@)"
#exit "${exit_value}"
} #}}}
#}}}
