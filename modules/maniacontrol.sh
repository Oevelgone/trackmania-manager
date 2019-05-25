#!/bin/bash
#shellcheck disable=SC2034,SC2154,SC2145,SC2015,SC2155

###############################################################################
#Maniacontrol controller functions
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
require_module "controllers"

declare -g MANIACONTROL_DIRECTORY="${MANIACONTROL_DIRECTORY:-ManiaControl}"

declare -gA MANIACONTROL_INIT_CONFIG_STRUCT=( #{{{
[keys]="xmlrpc_port sa_authpass db_user db_pass db_name"
#[key,section]="" [key,tag]="" [key,tag_def]=""
[xmlrpc_port,section]="server" [xmlrpc_port,tag]="port" [xmlrpc_port,tag_def]="port"       [xmlrpc_port,value]=""
[sa_authpass,section]="server" [sa_authpass,tag]="pass" [sa_authpass,tag_def]="password"   [sa_authpass,value]=""
[db_user,section]="database"   [db_user,tag]="user"     [db_user,tag_def]="mysql_user"     [db_user,value]=""
[db_pass,section]="database"   [db_pass,tag]="pass"     [db_pass,tag_def]="mysql_password" [db_pass,value]=""
[db_name,section]="database"   [db_name,tag]="name"     [db_name,tag_def]="database_name"   [db_name,value]=""
[masteradmins]="${CONTROLLER_ADMINS}"
) #}}}

declare -ga MANIACONTROL_EXIT_MESSAGES=( #{{{
"Runtime Error"
"Error while stopping maniacontrol \\\"%s\\\", timeout, check if maniacontrol closed successfully before trying to restart it."
"\\\"%s\\\" not found from \\\"%s\\\""
) #}}}

declare -gA SERVERS+=(
[SERVER_DEFAULT,maniacontrol_id]="%id%" [SERVER_DEFAULT,maniacontrol_config]="server.xml"
)

function find_maniacontrol_dir() { #Parameters -- {{{
if ! [[ "${MANIACONTROL_DIRECTORY}" =~ /.* ]]; then
    #Relative path
    if [ -e "${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}" ]; then
        MANIACONTROL_DIRECTORY="${SERVERS_ROOT_DIRECTORY%/}/${MANIACONTROL_DIRECTORY%/}"
    else
        exit_handler 2 "MANIACONTROL_EXIT_MESSAGES" "${MANIACONTROL_DIRECTORY%/}" "${SERVERS_ROOT_DIRECTORY%/}"
    fi
fi

check_file "${MANIACONTROL_DIRECTORY}" IS_DIR R W X || exit_handler "$?" "EXIT_INVALID_FILE" "${MANIACONTROL_DIRECTORY%/}"
} #}}}

function init_maniacontrol_server() { #Parameters -- {{{
require_module "database"
require_module "tm_vars"

local maniacontrol_root="${MANIACONTROL_DIRECTORY%/}"
#Check if Maniacontrol dir exist, else create it
if ! check_file "${SERVERS_ROOT_DIRECTORY}/ManiaControl" IS_DIR R W X; then
    echo "Create Maniacontrol dir"
    mkdir "${maniacontrol_root}/"
    tar -zxf "${TMMNG_RESOURCES_DIR%/}/controllers/Maniacontrol_Latest.tar.gz" -C "${maniacontrol_root}/" --strip 1
fi
#Copy config
local maniacontrol_config="${maniacontrol_root}/configs/maniacontrol_${server['id']}.xml"
cp "${maniacontrol_root}/configs/server.default.xml" "${maniacontrol_config}"
#Edit config
MANIACONTROL_INIT_CONFIG_STRUCT["xmlrpc_port,value"]="${server['xmlrpc_port']}"
MANIACONTROL_INIT_CONFIG_STRUCT["sa_authpass,value"]="${server['sa_authpass']}"
MANIACONTROL_INIT_CONFIG_STRUCT["db_user,value"]="${DATABASE_USER}"
MANIACONTROL_INIT_CONFIG_STRUCT["db_pass,value"]="${DATABASE_PASSWORD}"
MANIACONTROL_INIT_CONFIG_STRUCT["db_name,value"]="maniacontrol_${server['id']}"
for key in ${MANIACONTROL_INIT_CONFIG_STRUCT['keys']}; do
    sed -i -e "/<${MANIACONTROL_INIT_CONFIG_STRUCT["${key},section"]}>/,/<\/${MANIACONTROL_INIT_CONFIG_STRUCT["${key},section"]}>/\
{s/<${MANIACONTROL_INIT_CONFIG_STRUCT["${key},tag"]}>${MANIACONTROL_INIT_CONFIG_STRUCT["${key},tag_def"]}<\/${MANIACONTROL_INIT_CONFIG_STRUCT["${key},tag"]}>/\
<${MANIACONTROL_INIT_CONFIG_STRUCT["${key},tag"]}>${MANIACONTROL_INIT_CONFIG_STRUCT["${key},value"]}<\/${MANIACONTROL_INIT_CONFIG_STRUCT["${key},tag"]}>/}" \
"${maniacontrol_config}"
done
sed -i "s/<server>/<server id=\"${server['id']}\">/" "${maniacontrol_config}"
sed -i '/<login>admin_login<\/login>/d' "${maniacontrol_config}"
for user in ${MANIACONTROL_INIT_CONFIG_STRUCT['masteradmins']}; do
    sed -i "/\s*<\/masteradmins>/i <login>${user}<\/login>" "${maniacontrol_config}"
done
#Create database
mysql --user="${DATABASE_USER}" --password="${DATABASE_PASSWORD}" --execute="CREATE DATABASE maniacontrol_${server['id IF NOT EXISTS']};" 2> /dev/null
#Edit Manager config file
if ! grep "\[${server['id']},maniacontrol_config\]=" "${manager_config_file}" > /dev/null 2>&1; then
    sed -i "/^) # DO NOT MODIFY THIS LINE/i \[${server['id']},maniacontrol_config\]=\"maniacontrol_${server['id']}.xml\"" "${manager_config_file}"
elif grep "\[${server['id']},maniacontrol_config\]=\"maniacontrol_${server['id']}.xml\"" "${manager_config_file}" > /dev/null 2>&1; then
    #Do nothing all is good
    :
else
    # Replace
    sed -i "s/\[${server['id']},maniacontrol_config\]=.*$/\[${server['id']},maniacontrol_config\]=\"maniacontrol_${server['id']}.xml\"/" "${manager_config_file}"
fi
} #}}}

function start_maniacontrol() { #Parameters -- 1:(str)server_id {{{
LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
LOG LVERBOSE "Start maniacontrol ${1}"
local -i pid=0
local -i pid_to_kill=0
local -r server_id="${1:? $(exit_handler 2 EXIT_MESSAGES server_id 1)}"
local -r server_config="${2:? $(exit_handler 2 EXIT_MESSAGES server_config 2)}"

local -r maniacontrol_php="${MANIACONTROL_DIRECTORY%/}/ManiaControl.php"
local -r maniacontrol_pid_file="${MANIACONTROL_DIRECTORY%/}/${server_id}.pid"
local -r maniacontrol_log_dir="${MANIACONTROL_DIRECTORY%/}/logs"

check_file "${maniacontrol_php}" R || exit_handler "$?" "EXIT_INVALID_FILE" "${maniacontrol_php}"
check_file "${maniacontrol_pid_file}" R && pid=$(cat "${maniacontrol_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${maniacontrol_pid_file}"; }
#check_file "${maniacontrol_log_dir}" IS_DIR R W X || exit_handler "$?" "EXIT_INVALID_FILE" "${maniacontrol_log_dir}"
check_file "${maniacontrol_log_dir}" IS_DIR R W X || { local exit_value="$?"; [[ "${exit_value}" -eq 1 ]] && mkdir -p "${maniacontrol_log_dir}" || exit_handler "$?" "EXIT_INVALID_FILE" "${maniacontrol_log_dir}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ ^php.*${MANIACONTROL_DIRECTORY%/}/ManiaControl.php.* ]]; then
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
        exit_handler 1 "MANIACONTROL_EXIT_MESSAGES" "${server_id}"
    fi
done

cat << MCSTARTEOF > "${MANIACONTROL_DIRECTORY%/}/Maniacontrol_${server_id}.sh"
php "${maniacontrol_php}" -config="${server_config}" -id="${server_id}" -sh="Maniacontrol_${server_id}.sh" > "${maniacontrol_log_dir}/ManiaControl_${server_id}_$(date +%Y%m%d_%H%M).log" 2>&1 &
pid=$!
printf '%d' "${pid}" > "${maniacontrol_pid_file}"
MCSTARTEOF
chmod +x "${MANIACONTROL_DIRECTORY%/}/Maniacontrol_${server_id}.sh"
"${MANIACONTROL_DIRECTORY%/}/Maniacontrol_${server_id}.sh"

LOG LDEFAULT "ManiaControl started : ${server_id}"
} #}}}

#===  FUNCTION  ================================================================
#         NAME:  maniacontrol_stop
#  DESCRIPTION:  Stop maniacontrol
#===============================================================================
function maniacontrol_stop() { #Parameters -- {{{
local -i pid=0
local -i pid_to_kill=0

local -r maniacontrol_pid_file="${MANIACONTROL_DIRECTORY%/}/${server_info["name"]}.pid"

check_file "${maniacontrol_pid_file}" R && pid=$(cat "${maniacontrol_pid_file}") || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${maniacontrol_pid_file}"; }

#check if process might exist
if [ "${pid}" != 0 ]; then
    if [[ "$(check_file "/proc/${pid}/cmdline" && tr -d '\0' < /proc/"${pid}"/cmdline 2> /dev/null || printf '')" =~ .*python3\./manage\.py.*${server_info['name']}\.pid.* ]]; then
        pid_to_kill="${pid}"
    else
        pid=0
        check_file "$(dirname "${maniacontrol_pid_file}")" R W X && rm "${maniacontrol_pid_file}" || { local exit_value="$?"; [[ "${exit_value}" -gt 1 ]] && exit_handler "${exit_value}" "EXIT_INVALID_FILE" "${maniacontrol_pid_file}"; }
    fi
fi

if [ "${pid}" == 0 ]; then
    local -i return="$(pgrep -f "ManiaControl.php.*${server_info["name"]}" 2> /dev/null | head -n 1)"
    if [ "${return}" != 0 ]; then
        pid_to_kill="${return}"
    else
        return 0
    fi
fi

if [ "${pid_to_kill}" != 0 ]; then
    kill -15 "${pid_to_kill}"
    LOG LDEFAULT 'Maniacontrol stopped'
fi
}   # ----------  end of function maniacontrol_stop  ----------#}}}

function maniacontrol_running() { # Parameters -- 1:(str) server_id {{{
#"${server_info["maniacontrol_id"]}" "${server_info["maniacontrol_config"]}"
#local server_id="${1:? $(exit_handler 2 EXIT_MESSAGES server_id 1)}"
#local server_config="${2:? $(exit_handler 2 EXIT_MESSAGES server_config 1)}"
local server_id="${server_info["maniacontrol_id"]}"
local server_config="${server_info["maniacontrol_config"]}"

if pgrep -f "php.*${MANIACONTROL_DIRECTORY%/}/ManiaControl.php.*-config=${server_config} -id=${server_id}" > /dev/null 2>&1 ; then
    return 0
else
    return 1
fi
} #}}}

find_maniacontrol_dir
declare -gr MOD_MANIACONTROL_LOADED=true
