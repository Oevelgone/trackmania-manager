#!/bin/bash
#shellcheck disable=SC2034,SC2145,SC2120,SC2015,SC2155,SC2140

###############################################################################
#Servers functions
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

#############################################
#  ALL MODULE VARIABLES MUST BE GLOBAL !!!  #
#############################################


#--- SET ---------------------------------------------------------
# Servers actions
#{{{

function start_server() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "Start server ${1}"

require_module "controllers"

local line_cleanup="${LINE_CLEAR}"

#Internal function if a server is already_running
function _already_running_server() { #{{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
read_input_multichoice "Maniaplanet server \"${server_name}\" is already running, restart [y/n] ? " "y n"
case "${REPLY}" in
    y)
        stop_server "${server_name}"
        line_cleanup="${LINE_BACK}"
        ;;
    n)
        LOG LDEFAULT "Server \"${server_name}\" not restarted."
        controller_restart
        #if ! maniacontrol_running "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"; then
            #read_input_multichoice "Maniacontrol is not running for this server, do you want to restart it ? [y/n] ? " "y n"
            #case "${REPLY}" in
                #y)
                    #start_maniacontrol "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"
                    #;;
                #n)
                    #:
                    #;;
            #esac
        #fi
        return 1
        ;;
    *)
        exit_handler 0
        ;;
esac
} #}}}

local -i pid=0
local -r server_name="${1:? $(exit_handler 3 FUNCTION_EXIT_MESSAGES server_name 1)}"
local -A server_info=(
#[base]="$(read_server_config "base")"
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
[tracklist_dir]="$(read_server_config "${server_name}" "tracklist_dir")"
[tracklist]="$(read_server_config "${server_name}" "tracklist")"
[controller]="$(read_server_config "${server_name}" "controller")"
#[maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
#[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
)
controller_fill_server_info

local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"
#local -r server_tracklist_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["tracklist_dir"]%/}/${server_info["tracklist"]}"
local -r server_pid_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/.pid"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"

#Check if pid file exist
check_file "${server_pid_file}" R && pid=$(cat "${server_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${server_pid_file}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    LOG LDEBUG "in function ${FUNCNAME[0]} pid found in file \"${server_pid_file}\""
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ .*ManiaPlanetServer.* ]]; then
        #shellcheck disable=SC2119
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
        #shellcheck disable=SC2119
        _already_running_server || return 0 #return 0 if user decided not to restart the server.

    fi
fi

server_info+=(
[xml_port]="$(read_server_config_entry "system_config" "xmlrpc_port" "${server_config_file}")"
)

#no server running, so start
LOG LDEFAULT "${line_cleanup}Starting server, please wait..."
pid="$("${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/ManiaPlanetServer" "/dedicated_cfg=${server_info["config_file"]}" "/game_settings=${server_info["tracklist"]}" | grep -Eo "pid=[0-9]+" | awk -F "=" '{print $2}' &)"
LOG LDEBUG "in function ${FUNCNAME[0]} server started with pid ${pid}"

local timeout=$((SECONDS + 30))
until server_running "${server_info["xml_port"]}"; do
    if [ "${SECONDS}" -gt "${timeout}" ]; then
        kill -9 "${pid}" > /dev/null 2>&1
        exit_handler 1 "EXIT_SERVER_ERRORS" "${server_name}"
    fi
done
LOG LDEBUG " "
#shellcheck disable=SC2059
printf "$LINE_BACK"

printf '%s' "${pid}" > "${server_pid_file}"

LOG LDEFAULT "Server started : ${server_name}"

start_controller
#if [ "${server_info['controller']}" == "maniacontrol" ]; then
#start_maniacontrol "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"
#elif [ "${server_info['controller']}" == "pyplanet" ]; then
#require_module "pyplanet"
#start_pyplanet "${server_info["name"]}"
#fi
} #}}}

function stop_server() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "Stop server ${1}"

require_module "controllers"
#require_module "maniacontrol"

local -i pid=0
local -i pid_to_kill=0
local -r server_name="${1:? $(exit_handler 3 FUNCTION_EXIT_MESSAGES server_name 1)}"
local -A server_info=(
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
#[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
[controller]="$(read_server_config "${server_name}" "controller")"
)
controller_fill_server_info

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
#shellcheck disable=SC2059
printf "$LINE_BACK"

rm "${server_pid_file}" > /dev/null 2>&1

LOG LDEFAULT "Server stopped : ${server_name}"

controller_stop
} #}}}

function status_server() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "Status server ${1}"

require_module "controllers"

local -r server_name="${1:? $(exit_handler 3 FUNCTION_EXIT_MESSAGES server_name 1)}"
local -A server_info=(
#[base]="$(read_server_config "base")"
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
#[maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
#[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
[controller]="$(read_server_config "${server_name}" "controller")"
)
controller_fill_server_info

local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"
#local -r maniacontrol_config_file="${MANIACONTROL_DIRECTORY%/}/${MANIACONTROL_CONFIG_FILE}"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"

#if [ "${server_info['controller']}" == "maniacontrol" ]; then
#check_file "${maniacontrol_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${maniacontrol_config_file}"
#fi

server_info+=(
#[base]="$(read_server_config_entry "server_options" "base" "${server_config_file}")"
[server_port]="$(read_server_config_entry "system_config" "server_port" "${server_config_file}")"
)
LOG LDEFAULT "$(cat <<EOF
----- Server "${server_info["name"]}" : $(server_running "${server_info["server_port"]}" "0.0.0.0" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m") -----
$(controller_status)
EOF
#ManiaControl "${server_info["maniacontrol_id"]}" : $(maniacontrol_running "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m")
)"
LOG LDEFAULT " "
} #}}}

function info_server() { #Parameters -- 1:(str) Server name {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "Info server ${1}"

require_module "controllers"
#require_module "maniacontrol"

function _info_content() { #{{{
cat <<EOF
----- Server "${server_info["name"]}" : $(server_running "${server_info["server_port"]}" "0.0.0.0" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m") -----
Directory    -- %ServersRoot%/${server_info["dir"]%/}/
Config file  -- ./${server_info["config_dir"]%/}/${server_info["config_file"]}
Tracklist    -- ./${server_info["tracklist_dir"]%/}/${server_info["tracklist"]}
Server Ports -- Main : ${server_info["server_port"]} P2P : ${server_info["p2p_port"]} XMLRPC : ${server_info["xml_port"]}
Title        -- ${server_info["title"]}

Display Name         -- ${server_info["display_name"]}
Max Players          -- ${server_info["max_players"]}
Max Spectators       -- ${server_info["max_specs"]}
Players Password     -- ${server_info["servpasswd"]:-"No password"}
Spectators  Password -- ${server_info["specpasswd"]:-"No password"}

$(controller_info)

Port -- "${server_info["xml_port"]}"
User -- "${server_info["cuser"]}"
Pass -- "${server_info["cpass"]}"
EOF
#Host -- "${server_info["mchost"]}"
#ManiaControl server id : "${server_info["maniacontrol_id"]}" -- $(maniacontrol_running "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m")
#Directory   -- ./${MANIACONTROL_DIRECTORY#${SERVERS_ROOT_DIRECTORY}}/
#Config file -- ./${MANIACONTROL_CONFIG_FILE}
} #}}}

local -r server_name="${1:? $(exit_handler 3 FUNCTION_EXIT_MESSAGES server_name 1)}"
local -A server_info=(
#[base]="$(read_server_config "base")"
[name]="${server_name}"
[dir]="$(read_server_config "${server_name}" "dir" "%name%" "${server_name}")"
[config_dir]="$(read_server_config "${server_name}" "config_dir")"
[config_file]="$(read_server_config "${server_name}" "config_file")"
[tracklist_dir]="$(read_server_config "${server_name}" "tracklist_dir")"
[tracklist]="$(read_server_config "${server_name}" "tracklist")"
#[maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
#[maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")"
[controller]="$(read_server_config "${server_name}" "controller")"
)
controller_fill_server_info

local -r server_config_file="${SERVERS_ROOT_DIRECTORY%/}/${server_info["dir"]%/}/${server_info["config_dir"]%/}/${server_info["config_file"]}"
#local -r maniacontrol_config_file="${MANIACONTROL_DIRECTORY%/}/${MANIACONTROL_CONFIG_FILE}"

check_file "${server_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${server_config_file}"

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
#[chost]="$(read_server_config_entry "authorization_levels" "password" "${server_config_file}" "password")"
#[cport]="$(read_server_config_entry "authorization_levels" "password" "${server_config_file}" "password")"
[cuser]="$(read_server_config_entry "authorization_levels" "name" "${server_config_file}" "name")"
[cpass]="$(read_server_config_entry "authorization_levels" "password" "${server_config_file}" "password")"
#[chost]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "host" "${maniacontrol_config_file}" "server")"
#[cport]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "port" "${maniacontrol_config_file}" "server")"
#[cuser]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "user" "${maniacontrol_config_file}" "server")"
#[cpass]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "pass" "${maniacontrol_config_file}" "server")"
)
if [ "${USER_INTERFACE}" == "true" ]; then
    less -R <<< "$(_info_content)

    Press \"q\" to continue..."
else
    LOG LDEFAULT "$(_info_content)"
fi
} #}}}

function list_servers() { #Parameters --  {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "list servers"

local -i i=0
LOG LDEFAULT "Registered servers are :"
for server in ${SERVERS["list"]}; do
    LOG LDEFAULT "  $((++i)) - $server"
done
} #}}}

function server_running() { # Parameters -- 1:(int) Port Number, 2: IP {{{
local port="${1:? $(exit_handler 3 FUNCTION_EXIT_MESSAGES port_number 1)}"
local ip="${2:-127.0.0.1}"

if netstat -lntp 2>/dev/null | grep "${ip}:${port}" >/dev/null 2>&1 ; then
    return 0
else
    return 1
fi
} #}}}

#}}}
#-----------------------------------------------------------------------

declare -gr MOD_SERVERS_LOADED=true
