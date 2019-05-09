#!/bin/bash
#shellcheck disable=

###############################################################################
# TRACKMANIA SERVER MANAGER
#This script allow you to fully manage trackmania servers
#Features are : Install, Configure, Backup, Start/Stop, Handle Plugins
#Copyright (C) 2019 Navarra Manuel
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

## TODO
# xmlrpc
# handle logs
# config from non-bash file or database
# install server
# pyplanet support
# auto_restart
# auto_update
##


#######################################################################################################################
######################## DO NOT MODIFY THIS FILE, INSTEAD ENTER YOUR SETTINGS IN "config" FILE ########################
#######################################################################################################################

# Variables {{{
declare -r SCRIPT_LOCATION="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

declare -r USAGE_MESSAGE="Usage Message"

declare -a EXIT_MESSAGES=(
"Runtime Error"                                           ## 0
"The program encountered an unsupported error"            ## 1
"Missing %s \(_arg%d\)"                                   ## 2
""                                                        ## 3
""                                                        ## 4
""                                                        ## 5
""                                                        ## 6
""                                                        ## 7
""                                                        ## 8
""                                                        ## 9
"Server name \\\"%s\\\" is invalid for action \\\"%s\\\"" ## 10
#""                                                       ## 10
)
declare -a EXIT_INVALID_FILE=(
"Runtime Error"
"File \\\"%s\\\" does no exist"
"File \\\"%s\\\" exist but is not a directory"
"File \\\"%s\\\" cannot be read, check permissions"
"File \\\"%s\\\" cannot be written, check permissions"
"File \\\"%s\\\" cannot be executed/accessed, check permissions"
)
declare -a EXIT_SERVER_ERRORS=(
"Runtime Error"
"Server \\\"%s\\\" could not be started, timeout."
"Error while stopping server \\\"%s\\\", timeout, check if server closed successfully before trying to restart it."
"Error while stopping maniacontrol \\\"%s\\\", timeout, check if maniacontrol closed successfully before trying to restart it."
)

declare -A UI_MAIN_MENU=(
[list]="select start stop info refresh exit"
[select,title]="Select a server"           [select,cmd]="ui_server_select"
[start,title]="Start server"               [start,cmd]="start_server"
[stop,title]="Stop server"                 [stop,cmd]="stop_server"
[info,title]="Display server informations" [info,cmd]="info_server"
[refresh,title]="Refresh"                  [refresh,cmd]="ui_refresh"
[exit,title]="Exit"                        [exit,cmd]="ui_exit"
)

### DEFAULT CONFIG ###
declare SERVERS_ROOT_DIRECTORY="${HOME}"
declare -A SERVERS=(
[list]=""
[SERVER_DEFAULT,dir]="%name%" [SERVER_DEFAULT,config_file]="dedicated_cfg.txt" [SERVER_DEFAULT,config_dir]="UserData/Config"
[SERVER_DEFAULT,tracklist]="MatchSettings/tracklist.txt" [SERVER_DEFAULT,tracklist_dir]="UserData/Maps"
[SERVER_DEFAULT,maniacontrol_id]="%id%" [SERVER_DEFAULT,maniacontrol_config]="server.xml"
)

declare MANIACONTROL_DIRECTORY="ManiaControl"
declare MANIACONTROL_CONFIG_DIR="configs"
######################

declare USER_INTERFACE=false
declare UI_LOOP=false

declare -r bin_to_check="jq"
declare manager_config_file="${SCRIPT_LOCATION}/config"
declare -g current_server="all"

#}}}

# Includes
source ${SCRIPT_LOCATION}/includes/shared_functions.sh
source ${SCRIPT_LOCATION}/includes/ui.sh

# Functions

# functionnal {{{

function parse_args() { #Parameters -- $@ {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
eval set "${@}" --
while [ ! -z ${1:x} ]; do
    LOG LDEBUG "Arg 1 is : ${1:-empty}"
    case "${1}" in
        install)
            install_server "${2%--}"
            ;;
        start|stop|status|info)
            local action="${1}"
            local server_name="${2%--}"

            if [[ "${SERVERS["list"]}" == *"server_${server_name:?Missing server_name for action : ${action}}"* ]]; then
                server_name="server_${server_name}"
            fi

            if [ "${server_name}" == "all" ]; then
                LOG LDEBUG "Running command ${action}_server on all servers \"${SERVERS["list"]}\""
                for server in ${SERVERS["list"]}; do
                    ${action}_server "${server}"
                done
            elif [[ "${SERVERS["list"]}" != *"${server_name:?Missing server_name for action : ${action}}"* ]]; then
                exit_handler 10 EXIT_MESSAGES "${server_name}" "${action}"
            else
                ${action}_server "${server_name}"
            fi

            shift 2
            ;;
        list)
            list_servers
            shift
            ;;
        --)
            break
            ;;
        *)
            usage "Unsuported argument ${1}"
            ;;
    esac
done
} #}}}
function read_server_config() { #Parameters -- 1:(str) server_name, 2: ID, 3:(str) regex, 4:(str) Replace value {{{
local server_name="${1:? $(exit_handler 2 EXIT_MESSAGES ID 1)}"
local id="${2:? $(exit_handler 2 EXIT_MESSAGES ID 2)}"
printf '%s' "${SERVERS["${server_name},${id}"]:-"${SERVERS["SERVER_DEFAULT,${id}"]/"${3:-}"/${4:-}}"}"
} #}}}
function read_server_config_entry() { #Parameters -- 1:(str) Section, 2:(str) ID, 3:(str) server_config_file, 4(str) section_close[optional] {{{
local section="${1:? $(exit_handler 2 EXIT_MESSAGES Section 1)}"
local section_close="${4:-${section}}"
local id="${2:? $(exit_handler 2 EXIT_MESSAGES ID 2)}"
local l_config_file="${3:? $(exit_handler 2 EXIT_MESSAGES server_config_file 3)}"
printf '%s' "$(awk "/<${section}>/,/<\/${section_close}>/" "${l_config_file}" | grep "<${id}>" | awk -F "</?${id}>" '{ print $2  }')"
} #}}}
#}}}

# Servers action functions {{{
source ${SCRIPT_LOCATION}/modules/server_install.sh
function start_server() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
LOG LVERBOSE "Start server ${1}"
local line_cleanup="${LINE_CLEAR}"

#Internal function if a server is already_running
function _already_running_server() { #{{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
read_input_multichoice "Maniaplanet server \"${server_name}\" is already running, restart [y/n] ? " "y n"
case "${REPLY}" in
    y)
        stop_server "${server_name}"
        line_cleanup="${LINE_BACK}"
        ;;
    n)
        LOG LDEFAULT "Server \"${server_name}\" not restarted."
        if ! maniacontrol_running "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"; then
            read_input_multichoice "Maniacontrol is not running for this server, do you want to restart it ? [y/n] ? " "y n"
            case "${REPLY}" in
                y)
                    start_maniacontrol "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"
                    ;;
                n)
                    :
                    ;;
            esac
        fi
        return 1
        ;;
    *)
        exit_handler 0
        ;;
esac
} #}}}

local -i pid=0
local -r server_name="${1:? $(exit_handler 2 EXIT_MESSAGES Server_name 1)}"
local -A server_info=(
#[base]="$(read_server_config "base")"
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
[tracklist_dir]="$(read_server_config "${server_name}" "tracklist_dir")"
[tracklist]="$(read_server_config "${server_name}" "tracklist")"
[maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
)

local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"
local -r server_tracklist_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["tracklist_dir"]%/}/${server_info["tracklist"]}"
local -r server_pid_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/.pid"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"

#Check if pid file exist
check_file "${server_pid_file}" R && pid=$(cat "${server_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${server_pid_file}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    LOG LDEBUG "in function ${FUNCNAME[0]} pid found in file \"${server_pid_file}\""
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ .*ManiaPlanetServer.* ]]; then
        _already_running_server || return 0 #return 0 if user decided not to restart the server.
    else
        LOG LDEBUG "in function ${FUNCNAME[0]} reset pid and possibly remove \"${server_pid_file}\""
        pid=0
        check_file "$(dirname "${server_pid_file}")" R W X && rm "${server_pid_file}" || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${server_pid_file}"; }
    fi
fi

if [ "${pid}" == 0 ]; then
    LOG LDEBUG "in function ${FUNCNAME[0]} no pid found or pid reset, looking for pid from process"
    local -i return="$(pgrep -f "${SERVERS_ROOT_DIRECTORY%/}/${server_info["name"]}/ManiaPlanetServer" 2> /dev/null)"
    if [ "${return}" != 0 ]; then
        _already_running_server || return 0 #return 0 if user decided not to restart the server.

    fi
fi

server_info+=(
[xml_port]="$(read_server_config_entry "system_config" "xmlrpc_port" "${server_config_file}")"
)

#no server running, so start
LOG LDEFAULT "${line_cleanup}Starting server, please wait..."
pid="$(${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/ManiaPlanetServer "/dedicated_cfg=${server_info["config_file"]}" "/game_settings=${server_info["tracklist"]}" | grep -Eo "pid=[0-9]+" | awk -F "=" '{print $2}' &)"
LOG LDEBUG "in function ${FUNCNAME[0]} server started with pid ${pid}"

local timeout=$((SECONDS + 30))
until server_running "${server_info["xml_port"]}"; do
    if [ "${SECONDS}" -gt "${timeout}" ]; then
        kill -9 "${pid}" > /dev/null 2>&1
        exit_handler 1 "EXIT_SERVER_ERRORS" "${server_name}"
    fi
done
LOG LDEBUG " "
printf $LINE_BACK

printf '%s' "${pid}" > "${server_pid_file}"

LOG LDEFAULT "Server started : ${server_name}"

start_maniacontrol "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"
} #}}}
function start_maniacontrol() { #Parameters -- 1:(str)server_id {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
LOG LVERBOSE "Start maniacontrol ${1}"
local -i pid=0
local -i pid_to_kill=0
local -r server_id="${1:? $(exit_handler 2 EXIT_MESSAGES server_id 1)}"
local -r server_config="${2:? $(exit_handler 2 EXIT_MESSAGES server_config 2)}"

local -r maniacontrol_php="${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/ManiaControl.php"
local -r maniacontrol_pid_file="${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/${server_id}.pid"
local -r maniacontrol_log_dir="${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/logs"

check_file "${maniacontrol_php}" R || exit_handler "$?" "EXIT_INVALID_FILE" "${maniacontrol_php}"
check_file "${maniacontrol_pid_file}" R && pid=$(cat "${maniacontrol_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${maniacontrol_pid_file}"; }
check_file "${maniacontrol_log_dir}" IS_DIR R W X || exit_handler "$?" "EXIT_INVALID_FILE" "${maniacontrol_log_dir}"

#check if process might exist
if [ "${pid}" != 0 ]; then
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ ^php.*${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/ManiaControl.php.* ]]; then
        pid_to_kill="${pid}"
    else
        pid=0
        check_file "$(dirname "${maniacontrol_pid_file}")" R W X && rm "${maniacontrol_pid_file}" || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${maniacontrol_pid_file}"; }
    fi
fi

if [ "${pid}" == 0 ]; then
    local -i return="$(pgrep -f "${SERVERS_ROOT_DIRECTORY%/}.*ManiaControl.php.*-config=${server_config} -id=${server_id}" -sh="Maniacontrol_${server_id}.sh" 2> /dev/null)"
    if [ "${return}" != 0 ]; then
        pid_to_kill="${return}"
    fi
fi

if [ "${pid_to_kill}" != 0 ]; then
    kill -15 "${pid_to_kill}"
fi

local timeout=$((SECONDS + 10))
until ! [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ ^php.*ManiaControl.php.* ]]; do
    if [ "${SECONDS}" -gt "${timeout}" ]; then
        exit_handler 3 "EXIT_SERVER_ERRORS" "${server_id}"
    fi
done

cat << MCSTARTEOF > "${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/Maniacontrol_${server_id}.sh"
php "${maniacontrol_php}" -config="${server_config}" -id="${server_id}" -sh="Maniacontrol_${server_id}.sh" > "${maniacontrol_log_dir}/ManiaControl_${server_id}_$(date +%Y%m%d_%H%M).log" 2>&1 & #TODO server_config distintion
pid=$!
printf '%d' "${pid}" > "${maniacontrol_pid_file}"
MCSTARTEOF
chmod +x "${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/Maniacontrol_${server_id}.sh"
"${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/Maniacontrol_${server_id}.sh"

LOG LDEFAULT "ManiaControl started : ${server_id}"
} #}}}
function stop_server() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
LOG LVERBOSE "Stop server ${1}"

local -i pid=0
local -i pid_to_kill=0
local -r server_name="${1:? $(exit_handler 2 EXIT_MESSAGES Server_name 1)}"
local -A server_info=(
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
)

#Check if pid file exist
local -r server_pid_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/.pid"
local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"
check_file "${server_pid_file}" R && pid=$(cat "${server_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${server_pid_file}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ .*ManiaPlanetServer.* ]]; then
        pid_to_kill="${pid}"
    else
        pid=0
        check_file "$(dirname "${server_pid_file}")" R W X && rm "${server_pid_file}" || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${server_pid_file}"; }
    fi
fi

if [ "${pid}" == 0 ]; then
    local -i return="$(pgrep -f "${SERVERS_ROOT_DIRECTORY%/}/${server_info["name"]}/ManiaPlanetServer" 2> /dev/null)"
    if [ "${return}" != 0 ]; then
        pid_to_kill="${return}"
    else
        return 0
    fi
fi

LOG LDEFAULT 'Server shutdown in progress, please wait...'
kill -15 "${pid_to_kill}"

server_info+=(
[server_port]="$(read_server_config_entry "system_config" "server_port" "${server_config_file}")"
)

local timeout=$((SECONDS + 10))
until ! server_running "${server_info["server_port"]}" "0.0.0.0"; do
    if [ "${SECONDS}" -gt "${timeout}" ]; then
        exit_handler 2 "EXIT_SERVER_ERRORS" "${server_name}"
    fi
done
LOG LDEBUG " "
printf $LINE_BACK

rm "${server_pid_file}" > /dev/null 2>&1

LOG LDEFAULT "Server stopped : ${server_name}"
} #}}}
function status_server() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
LOG LVERBOSE "Status server ${1}"
local -r server_name="${1:? $(exit_handler 2 EXIT_MESSAGES Server_name 1)}"
local -A server_info=(
#[base]="$(read_server_config "base")"
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
[maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
)

local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"
local -r maniacontrol_config_file="${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/${MANIACONTROL_CONFIG_FILE}"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"
check_file "${maniacontrol_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${maniacontrol_config_file}"

server_info+=(
#[base]="$(read_server_config_entry "server_options" "base" "${server_config_file}")"
[server_port]="$(read_server_config_entry "system_config" "server_port" "${server_config_file}")"
)
LOG LDEFAULT "$(cat <<EOF
----- Server "${server_info["name"]}" : $(server_running "${server_info["server_port"]}" "0.0.0.0" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m") -----
ManiaControl "${server_info["maniacontrol_id"]}" : $(maniacontrol_running "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m")
EOF
)"
LOG LDEFAULT " "
} #}}}
function info_server() { #Parameters -- 1:(str) Server name {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
LOG LVERBOSE "Info server ${1}"

function _info_content() { #{{{
cat <<EOF
----- Server "${server_info["name"]}" : $(server_running "${server_info["server_port"]}" "0.0.0.0" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m") -----
Directory    -- ${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/
Config file  -- ./${server_info["config_dir"]%/}/${server_info["config_file"]}
Tracklist    -- ./${server_info["tracklist_dir"]%/}/${server_info["tracklist"]}
Server Ports -- Main : ${server_info["server_port"]} P2P : ${server_info["p2p_port"]} XMLRPC : ${server_info["xml_port"]}
Title        -- ${server_info["title"]}

Display Name         -- ${server_info["display_name"]}
Max Players          -- ${server_info["max_players"]}
Max Spectators       -- ${server_info["max_specs"]}
Players Password     -- ${server_info["servpasswd"]:-"No password"}
Spectators  Password -- ${server_info["specpasswd"]:-"No password"}

ManiaControl server id : "${server_info["maniacontrol_id"]}" -- $(maniacontrol_running "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m")
Directory   -- ${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/
Config file -- ./${MANIACONTROL_CONFIG_FILE}

Host -- "${server_info["mchost"]}"
port -- "${server_info["mcport"]}"
user -- "${server_info["mcuser"]}"
pass -- "${server_info["mcpass"]}"
EOF
} #}}}

local -r server_name="${1:? $(exit_handler 2 EXIT_MESSAGES Server_name 1)}"
local -A server_info=(
#[base]="$(read_server_config "base")"
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
[tracklist_dir]="$(read_server_config "${server_name}" "tracklist_dir")"
[tracklist]="$(read_server_config "${server_name}" "tracklist")"
[maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
)

local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"
local -r maniacontrol_config_file="${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/${MANIACONTROL_CONFIG_FILE}"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"
check_file "${maniacontrol_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${maniacontrol_config_file}"

server_info+=(
#[base]="$(read_server_config_entry "server_options" "base" "${server_config_file}")"
[display_name]="$(read_server_config_entry "server_options" "name" "${server_config_file}")"
[max_players]="$(read_server_config_entry "server_options" "max_players" "${server_config_file}")"
[max_specs]="$(read_server_config_entry "server_options" "max_spectators" "${server_config_file}")"
[servpasswd]="$(read_server_config_entry "server_options" "password" "${server_config_file}")"
[specpasswd]="$(read_server_config_entry "server_options" "password_spectator" "${server_config_file}")"
[server_port]="$(read_server_config_entry "system_config" "server_port" "${server_config_file}")"
[p2p_port]="$(read_server_config_entry "system_config" "server_p2p_port" "${server_config_file}")"
[xml_port]="$(read_server_config_entry "system_config" "xmlrpc_port" "${server_config_file}")"
[title]="$(read_server_config_entry "system_config" "title" "${server_config_file}")"
[mchost]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "host" "${maniacontrol_config_file}" "server")"
[mcport]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "port" "${maniacontrol_config_file}" "server")"
[mcuser]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "user" "${maniacontrol_config_file}" "server")"
[mcpass]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "pass" "${maniacontrol_config_file}" "server")"
)
#declare -p server_info
local display_cmd
if [ "${USER_INTERFACE}" == "true" ]; then
    less -R <<< "$(_info_content)

    Press \"q\" to continue..."
else
    LOG LDEFAULT "$(_info_content)"
fi
} #}}}
function list_servers() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$(echo $@)\""
LOG LVERBOSE "list servers"

local -i i=0
LOG LDEFAULT "Registered servers are :"
for server in ${SERVERS["list"]}; do
    LOG LDEFAULT "  $((++i)) - $server"
done
} #}}}

function server_running() { # Parameters -- 1:(int) Port Number, 2: IP {{{
local port="${1:? $(exit_handler 2 EXIT_MESSAGES Port_number 1)}"
local ip="${2:-127.0.0.1}"

if netstat -lntp 2>/dev/null | grep "${ip}:${port}" >/dev/null 2>&1 ; then
    return 0
else
    return 1
fi
} #}}}
function maniacontrol_running() { # Parameters -- 1:(str) server_id {{{
local server_id="${1:? $(exit_handler 2 EXIT_MESSAGES server_id 1)}"
local server_config="${2:? $(exit_handler 2 EXIT_MESSAGES server_config 1)}"

if pgrep -f "php.*${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}/ManiaControl.php.*-config=${server_config} -id=${server_id}" > /dev/null 2>&1 ; then
    return 0
else
    return 1
fi
} #}}}
#}}}

# UI {{{
function ui_main_menu_entry() { #{{{
local entry=${1:?$(exit_handler 2 EXIT_MESSAGES entry 1)}
local key=${menu_keys[$(array_index "${entry}" "${menu_list[@]}")]}
if [[ "${_menu_structure["${key},cmd"]}" =~ .*_server$ ]]; then
    parse_args ${_menu_structure["${key},cmd"]%_server} "${current_server}"
    if [ "${key}" != "info" ]; then
        pause_key
    fi
else
    ${_menu_structure["${key},cmd"]}
fi
} #}}}
function ui_server_select_entry() { #{{{
local entry=${1:?$(exit_handler 2 EXIT_MESSAGES entry 1)}
if [ "${entry}" == "all" ] || match_in_list "${entry}" "${SERVERS["list"]}"; then
    current_server="${entry}"
fi
} #}}}
function ui_server_select() { #{{{
local -a UI_SERVER_SELECT=(
"title;Server Selection"
"info;Select the server you want to control (current server \"${current_server}\") :"
"menu;UI_SERVER_SELECT_MENU;ui_server_select_entry"
)
local -A UI_SERVER_SELECT_MENU=(
[list]="${SERVERS["list"]} all"
)

print_ui UI_SERVER_SELECT
pause_key
} #}}}
function server_set() { #{{{
current_server=${1:?$(exit_handler 2 EXIT_MESSAGES 'server_name' 1)}
} #}}}
function ui_refresh() { #{{{
:
} #}}}
function ui_exit() { #{{{
UI_LOOP=false
} #}}}
#}}}

# Getopt {{{
get_opt_verbose "c:h" "config:,help,ui" "$@"

eval set -- "${ARGS}";

while true; do
    case ${1} in
        -v|--verbose)
            shift 2;;
        -h|--help)
            usage
            shift;;
        --ui)
            LOG LDEBUG "using ui"
            USER_INTERFACE=true
            shift;;
        -c|--config)
            [[ -n "${2}" ]] && \
            {
                LOG LDEBUG "using config file ${2}"
                manager_config_file="${2}"
                shift 2
            } || exit 2;;
        --)
            shift
            break;;
        *)
            usage
            exit_handler 1
            ;;
    esac
done
#}}}

# MAIN

# Check for missing binarys
bin_check "${bin_to_check}"

# Read config file
LOG LDEBUG "loading config"
check_file "${manager_config_file}" R && {
source "${manager_config_file}"
LOG LDEBUG "loaded config file : ${manager_config_file}"
} || exit_handler $? "EXIT_INVALID_FILE" "${manager_config_file}"


if [ "${USER_INTERFACE}" == "true" ]; then
    LOG LDEBUG "Launching UI"

    UI_LOOP=true
    while [ "${UI_LOOP}" = "true" ]; do
        UI_COMP=("title;Trackmania server Manager" "cmd;parse_args;status all" "info;Current server \"${current_server}\"" "menu;UI_MAIN_MENU;ui_main_menu_entry") # I didn't split this line because it trigger an indent error...
        print_ui UI_COMP
    done
    read -sn 1 -p "Press any key to exit..."
    clear
else
    LOG LDEBUG "parsing args"
    parse_args "${ARGS}"
fi

exit 0
