#!/bin/bash
#shellcheck disable=SC2034,SC2154

###############################################################################
#Controllers functions
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

declare -g CONTROLLER_ACTIVE=""

declare -g CONTROLLERS_VALID=" pyplanet maniacontrol "
declare -g CONTROLLER_ADMINS="${CONTROLLER_ADMINS:-}"

declare -ga CONTROLLERS_EXIT_MESSAGES=( #{{{
"Runtime error"
"Unsupported controller \\\"%s\\\""
) #}}}

function set_controller() { #Parameters -- 1:(str) controller {{{
local controller="${1}"

if ! [[ "${CONTROLLERS_VALID}" =~ .*${controller}.* ]]; then
    exit_handler 1 "CONTROLLERS_EXIT_MESSAGES" "${controller}"
fi

if [ "${CONTROLLER_ACTIVE}" != "${controller}" ]; then
    CONTROLLER_ACTIVE="${controller}"
    require_module "${CONTROLLER_ACTIVE}"
fi
} #}}}

function init_controller_server() { #Parameters -- 1:(str) controller {{{
local controller="${1:? $(exit_handler 3 EXIT_MESSAGES controller 1)}"
set_controller "${controller}"

init_"${CONTROLLER_ACTIVE}"_server
} #}}}

function start_controller() { #Parameters -- {{{
local controllers="${1:-${server_info['controller']}}"
for controller in ${controllers}; do
    set_controller "${controller}"
    if [ "${CONTROLLER_ACTIVE}" == "maniacontrol" ]; then
        start_maniacontrol "${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"
    elif [ "${CONTROLLER_ACTIVE}" == "pyplanet" ]; then
        start_pyplanet "${server_info["name"]}"
    fi
done
} #}}}

#===  FUNCTION  ================================================================
#         NAME:  controller_stop
#  DESCRIPTION:  Stop controller if running
#===============================================================================
function controller_stop() { #Parameters -- 1:(str) controller {{{
local controllers="${1:-${server_info['controller']}}"
for controller in ${controllers}; do
    set_controller "${controller}"
    "${CONTROLLER_ACTIVE}_stop"
done
}   # ----------  end of function controller_stop  ----------#}}}

function controller_fill_server_info() { #Parameters -- {{{
for controller in ${server_info['controller']}; do
    set_controller "${controller}"
    if [ "${CONTROLLER_ACTIVE}" == "maniacontrol" ]; then
        server_info+=([maniacontrol_config]="$(read_server_config "${server_name}" "maniacontrol_config")"
        [maniacontrol_id]="$(read_server_config "${server_name}" "maniacontrol_id" "%id%" "${server_name}")")
        maniacontrol_config_file="${MANIACONTROL_DIRECTORY%/}/configs/${server_info['maniacontrol_config']}"
        check_file "${maniacontrol_config_file}" R || exit_handler $? "EXIT_INVALID_FILE" "${maniacontrol_config_file}"
        #server_info+=([mchost]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "host" "${maniacontrol_config_file}" "server")"
        #[mcport]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "port" "${maniacontrol_config_file}" "server")"
        #[mcuser]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "user" "${maniacontrol_config_file}" "server")"
        #[mcpass]="$(read_server_config_entry "server id=\"${server_info["maniacontrol_id"]}\"" "pass" "${maniacontrol_config_file}" "server")")
        #elif [ "${CONTROLLER_ACTIVE}" == "pyplanet" ]; then
        #:
    fi
done
} #}}}

function controller_status() { #Parameters -- {{{
for controller in ${server_info['controller']}; do
    set_controller "${controller}"
    local controller_name=""
    if [ "${CONTROLLER_ACTIVE}" == "maniacontrol" ]; then
        controller_name="${server_info["maniacontrol_id"]}"
    elif [ "${CONTROLLER_ACTIVE}" == "pyplanet" ]; then
        controller_name="${server_info["name"]}"
    fi
    printf "%s \"%s\" : %s" "${CONTROLLER_ACTIVE^}" "${controller_name}" \
    "$("${CONTROLLER_ACTIVE}_running" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m")"
done
} #}}}

function controller_info() { #Parameters --  {{{
for controller in ${server_info['controller']}; do
    set_controller "${controller}"
    local controller_name="" controller_directory="" controller_config_file=""
    if [ "${CONTROLLER_ACTIVE}" == "maniacontrol" ]; then
        controller_name="${server_info["maniacontrol_id"]}"
        controller_directory="${MANIACONTROL_DIRECTORY/${SERVERS_ROOT_DIRECTORY}/%ServersRoot%}"
        controller_config_file="${server_info['maniacontrol_config']}"
    elif [ "${CONTROLLER_ACTIVE}" == "pyplanet" ]; then
        controller_name="${server_info["name"]}"
        controller_directory="${PYPLANET_DIRECTORY/${SERVERS_ROOT_DIRECTORY}/%ServersRoot%}"
        controller_config_file="base.py"
    fi
    printf "%s \"%s\" : %s\n" "${CONTROLLER_ACTIVE^}" "${controller_name}" \
    "$("${CONTROLLER_ACTIVE}_running" && printf "\e[32mRunning\e[0m" || printf "\e[31mStopped\e[0m")"
    printf 'Directory   -- %s\n' "${controller_directory}/${server_info['name']}"
    printf 'Config file -- %s\n' "${controller_config_file}"
done
} #}}}

#===  FUNCTION  ================================================================
#         NAME:  controller_restart
#  DESCRIPTION:  Check if controllers need restart
#===============================================================================
function controller_restart() { #Parameters -- {{{
for controller in ${server_info['controller']}; do
    set_controller "${controller}"
    if ! "${CONTROLLER_ACTIVE}_running"; then
        read_input_multichoice "${CONTROLLER_ACTIVE^} is not running for this server, do you want to restart it ? [y/n] ? " "y n"
        case "${REPLY}" in
            y)
                start_controller "${CONTROLLER_ACTIVE}"
                ;;
            n)
                :
                ;;
        esac
    fi
done
}   # ----------  end of function controller_restart  ----------#}}}

declare -gr MOD_CONTROLLERS_LOADED=true
