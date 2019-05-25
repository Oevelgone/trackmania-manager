#!/bin/bash
#shellcheck disable=SC2034,SC2154,SC2145,SC2015,SC2155

###############################################################################
#Pyplanet controller functions
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

declare -g PYPLANET_DIRECTORY="${PYPLANET_DIRECTORY:-${HOME}/pyplanet}"
declare -ga PYPLANET_EXIT_MESSAGES=( #{{{
"Runtime Error"
"Error while stopping pyplanet \\\"%s\\\", timeout, check if maniacontrol closed successfully before trying to restart it."
) #}}}

function init_pyenv() { #Parameters -- {{{
export PATH="${HOME}/.pyenv/bin:$PATH"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"
pyenv activate "pyplanet-3.7.0" > /dev/null 2>&1
} #}}}

function init_pyplanet_server() { #Parameters -- 1: {{{
require_module "controllers"
require_module "database"
#TODO If server previously existed ?
# For moment remove previous pyplanet
if check_file "${PYPLANET_DIRECTORY%/}/${server['id']}" IS_DIR; then
    #shellcheck disable=SC2115
    rm -r "${PYPLANET_DIRECTORY%/}/${server['id']}" > /dev/null 2>&1
fi
##
cd "${PYPLANET_DIRECTORY%/}" || echo "Failed to cd ${PYPLANET_DIRECTORY%/}"

pyplanet init_project "${server['id']}" 2> /dev/null

# Replace :
# owners , Database (create), Dedicated, map matchsettings
masteradmins="$(for user in ${CONTROLLER_ADMINS}; do printf "'%s', " "${user}"; done)"
sed -i -e "s/'your-maniaplanet-login'/${masteradmins%, }/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"
sed -i -e "s/'NAME': 'pyplanet',/'NAME': 'pyplanet_${server['id']}',/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"
sed -i -e "s/'user': 'root',/'user': '${DATABASE_USER}',/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"
sed -i -e "s/'password': '',/'password': '${DATABASE_PASSWORD}',/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"
sed -i -e "s/'PORT': '5000',/'PORT': '${server['xmlrpc_port']}',/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"
sed -i -e "s/'PASSWORD': 'SuperAdmin',/'PASSWORD': '${server['sa_authpass']}',/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"
sed -i -e "s/'default': 'maplist.txt',/'default': 'tracklist.txt',/" "${PYPLANET_DIRECTORY%/}/${server['id']}/settings/base.py"


mysql --user="${DATABASE_USER}" --password="${DATABASE_PASSWORD}" --execute="CREATE DATABASE pyplanet_${server['id']} IF NOT EXISTS CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2> /dev/null
#CREATE DATABASE pyplanet CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
} #}}}

function start_pyplanet() { #Parameters -- 1:(str) server_name {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "Start pyplanet ${1}"
local -i pid=0
local -i pid_to_kill=0
local -r server_id="${1:? $(exit_handler 2 EXIT_MESSAGES server_id 1)}"

local -r pyplanet_exec="${PYPLANET_DIRECTORY%/}/${server_id}/manage.py"
local -r pyplanet_pid_file="${PYPLANET_DIRECTORY%/}/${server_id}/pyplanet_${server_id}.pid"
#local -r pyplanet_log_dir="${PYPLANET_DIRECTORY%/}/${server_id}/logs"

check_file "${pyplanet_exec}" R || exit_handler "$?" "EXIT_INVALID_FILE" "${pyplanet_exec}"
check_file "${pyplanet_pid_file}" R && pid=$(cat "${pyplanet_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${pyplanet_pid_file}"; }
#check_file "${pyplanet_log_dir}" IS_DIR R W X || { local exit_value="$?"; [[ "${exit_value}" -eq 1 ]] && mkdir -p "${pyplanet_log_dir}" || exit_handler "$?" "EXIT_INVALID_FILE" "${pyplanet_log_dir}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    #if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ python3.*${PYPLANET_DIRECTORY%/}/${server_id}/manage.py start --detach --pid-file=${server_id}.pid ]]; then
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ python3\ ${PYPLANET_DIRECTORY%/}/${server_id}/manage.py.*${server_id}.pid ]]; then
        pid_to_kill="${pid}"
    else
        pid=0
        check_file "$(dirname "${pyplanet_pid_file}")" R W X && rm "${pyplanet_pid_file}" || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${pyplanet_pid_file}"; }
    fi
fi

if [ "${pid}" == 0 ]; then
    local -i return="$(pgrep -f "python3.*${PYPLANET_DIRECTORY%/}/${server_id}/manage.py start --detach --pid-file=${server_id}.pid" 2> /dev/null)"
    if [ "${return}" != 0 ]; then
        pid_to_kill="${return}"
    fi
fi

if [ "${pid_to_kill}" != 0 ]; then
    kill -15 "${pid_to_kill}"
fi

local timeout=$((SECONDS + 10))
until ! [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ ^python3.*manage.py.* ]]; do
    if [ "${SECONDS}" -gt "${timeout}" ]; then
        exit_handler 1 "PYPLANET_EXIT_MESSAGES" "${server_id}"
    fi
done

local save_dir="${PWD}"

cd "${PYPLANET_DIRECTORY%/}/${server_id}" || return
./manage.py start --detach --pid-file="pyplanet_${server_id}.pid"
cd "${save_dir}" || return
} #}}}

#===  FUNCTION  ================================================================
#         NAME:  pyplanet_stop
#  DESCRIPTION:  Stop pyplanet
#===============================================================================
function pyplanet_stop() { #Parameters -- {{{
local -i pid=0
local -i pid_to_kill=0

local -r pyplanet_pid_file="${PYPLANET_DIRECTORY%/}/${server_info["name"]%/}/pyplanet_${server_info['name']}.pid"

check_file "${pyplanet_pid_file}" R && pid=$(cat "${pyplanet_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${pyplanet_pid_file}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ .*python3\./manage\.py.*${server_info['name']}\.pid.* ]]; then
        pid_to_kill="${pid}"
    else
        pid=0
        check_file "$(dirname "${pyplanet_pid_file}")" R W X && rm "${pyplanet_pid_file}" || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${pyplanet_pid_file}"; }
    fi
fi

if [ "${pid}" == 0 ]; then
    local -i return="$(pgrep -f "manage.py.*${server_info["name"]}" 2> /dev/null | head -n 1)"
    if [ "${return}" != 0 ]; then
        pid_to_kill="${return}"
    else
        return 0
    fi
fi

if [ "${pid_to_kill}" != 0 ]; then
    kill -15 "${pid_to_kill}"
    LOG LDEFAULT 'Pyplanet stopped'
fi
}   # ----------  end of function pyplanet_stop  ----------#}}}

function pyplanet_running() { # Parameters -- 1:(str) server_id {{{
#local server_id="${1:? $(exit_handler 2 EXIT_MESSAGES server_id 1)}"
#local server_config="${2:? $(exit_handler 2 EXIT_MESSAGES server_config 1)}"
local server_id="${server_info["name"]}"

if pgrep -f "python3 \./manage\.py.*--pid-file=pyplanet_${server_id}.pid" > /dev/null 2>&1 ; then
    return 0
else
    return 1
fi
} #}}}

init_pyenv
declare -gr MOD_PYPLANET_LOADED=true
