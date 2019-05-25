#!/bin/bash
#shellcheck disable=SC2145,SC2119,2120

###############################################################################
#Set of functions to install a trackmania server
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

require_module "tm_vars"
## pyenv activate pyplanet-3.7.0

declare -gri TMMNG_INST_PORT_DEFAULT=2350
declare -gri TMMNG_INST_P2P_PORT_DEFAULT=3450
declare -gri TMMNG_INST_XMLRPC_PORT_DEFAULT=5000

declare -gA TMMNG_INST_KEYS_STRUCT=( #{{{
[keys]="id mp_login mp_password titlepack name comment controller players spectators
port p2p_port xmlrpc_port
sa_authpass a_authpass u_authpass p_copass s_copass"
#[key,default]="" [key,passoc]=""
#[key,section]="" [key,tag]="" [key,tag_def]=""
[id,default]=""                              [id,passoc]="id"
[id,section]="none"                          [id,tag]="none"                         [id,tag_def]=""
[mp_login,default]=""                        [mp_login,passoc]="login"
[mp_login,section]="masterserver_account"    [mp_login,tag]="login"                  [mp_login,tag_def]=""
[mp_password,default]=""                     [mp_password,passoc]="password"
[mp_password,section]="masterserver_account" [mp_password,tag]="password"            [mp_password,tag_def]=""
[titlepack,default]=""                       [titlepack,passoc]="titlepack"
[titlepack,section]="system_config"          [titlepack,tag]="title"                 [titlepack,tag_def]="SMStorm"
[name,default]=""                            [name,passoc]="name"
[name,section]="server_options"              [name,tag]="name"                       [name,tag_def]=""
[comment,default]=""                         [comment,passoc]="comment"
[comment,section]="server_options"           [comment,tag]="coment"                  [comment,tag_def]=""
[controller,default]=""                      [controller,passoc]="controller"
[controller,section]="none"                  [controller,tag]="none"                 [controller,tag_def]=""
[players,default]="100"                      [players,passoc]="players"
[players,section]="server_options"           [players,tag]="max_players"             [players,tag_def]="32"
[spectators,default]="50"                    [spectators,passoc]="spectators"
[spectators,section]="server_options"        [spectators,tag]="max_spectators"       [spectators,tag_def]="32"
[port,default]=""                            [port,passoc]="port"
[port,section]="system_config"               [port,tag]="server_port"                [port,tag_def]="2350"
[p2p_port,default]="3450"                    [p2p_port,passoc]="p2p_port"
[p2p_port,section]="system_config"           [p2p_port,tag]="server_p2p_port"        [p2p_port,tag_def]="3450"
[xmlrpc_port,default]="5000"                 [xmlrpc_port,passoc]="xmlrpc_port"
[xmlrpc_port,section]="system_config"        [xmlrpc_port,tag]="xmlrpc_port"         [xmlrpc_port,tag_def]="5000"
[sa_authpass,default]="passwd"               [sa_authpass,passoc]="sa_password"
[sa_authpass,section]="authorization_levels" [sa_authpass,tag]="password"            [sa_authpass,tag_def]="SuperAdmin"
[a_authpass,default]="passwd"                [a_authpass,passoc]="a_password"
[a_authpass,section]="authorization_levels"  [a_authpass,tag]="password"             [a_authpass,tag_def]="Admin"
[u_authpass,default]="passwd"                [u_authpass,passoc]="u_password"
[u_authpass,section]="authorization_levels"  [u_authpass,tag]="password"             [u_authpass,tag_def]="User"
[p_copass,default]="NULLPASSWORD"            [p_copass,passoc]="players_password"
[p_copass,section]="server_options"          [p_copass,tag]="password"               [p_copass,tag_def]=""
[s_copass,default]="NULLPASSWORD"            [s_copass,passoc]="spectators_password"
[s_copass,section]="server_options"          [s_copass,tag]="password_spectator"     [s_copass,tag_def]=""
) #}}}

function install_server() { #Parameters --  {{{
#declare -p
local -A server=()
local read_infos=true

LOG LDEBUG "Called function ${FUNCNAME[0]} with parameters \"$@\""
#LOG LDEFAULT "This function is not implemented yet."

for key in ${TMMNG_INST_KEYS_STRUCT['keys']}; do
    server["${key}"]="${TMMNG_INST_KEYS_STRUCT["${key},default"]}"
done

if [ -n "${1}" ]; then
    install_server_parse_infos "${1}"
fi

if ${read_infos}; then
    install_server_read_infos
fi

#declare -p server

#TODO Checks

# Compute Ports
port_diff="$(( "${server['port']}" - "${TMMNG_INST_PORT_DEFAULT}" ))"

if [ "$(( "${server['p2p_port']} - "${TMMNG_INST_P2P_PORT_DEFAULT} ))" != "${port_diff}" ]; then
    server['p2p_port']="$(( "${TMMNG_INST_P2P_PORT_DEFAULT}" + "${port_diff}" ))"
fi
if [ "$(( "${server['xmlrpc_port']} - "${TMMNG_INST_XMLRPC_PORT_DEFAULT} ))" != "${port_diff}" ]; then
    server['xmlrpc_port']="$(( "${TMMNG_INST_XMLRPC_PORT_DEFAULT}" + "${port_diff}" ))"
fi

#Randomize Auth Password
for key in ${TMMNG_INST_KEYS_STRUCT['keys']}; do
    if [[ "${key}" =~ .*_authpass ]] && [ "${server["${key}"]}" == "passwd" ]; then
        server["${key}"]="$(< /dev/urandom tr -dc A-Za-z0-9 | head -c32;echo;)"
    fi
done

# Remove unwanted connect passwords
for key in ${TMMNG_INST_KEYS_STRUCT['keys']}; do
    if [[ "${key}" =~ .*_copass ]] && [ "${server["${key}"]}" == "NULLPASSWORD" ]; then
        server["${key}"]=""
    fi
done


deploy_server
} #}}}

function install_server_parse_infos() { #Parameters -- 1:(str) serialized_infos {{{
local serialized_infos="${1:? $(exit_handler 3 EXIT_MESSAGES serialized_infos 1)}"

read_infos=false

for key in ${TMMNG_INST_KEYS_STRUCT['keys']}; do
    server["${key}"]=$(jq -r ".${TMMNG_INST_KEYS_STRUCT["${key},passoc"]}" <<< "${serialized_infos}")
    if [ "${server["${key}"]}" == "null" ] && [ "${key}" != "comment" ]; then
        if [ -n "${TMMNG_INST_KEYS_STRUCT["${key},default"]}" ]; then
            server["${key}"]="${TMMNG_INST_KEYS_STRUCT["${key},default"]}"
        else
            read_infos=true
        fi
    fi
done

#TODO Checks
} #}}}

function install_server_read_infos() { #Parameters -- {{{
# Read server name, Maniaplanet login and password
read -rp "Server Unique-ID [server_001] : " server["id"]
#TODO check if server already exist and parse name chars
echo "Maniaplanet server credentials"
read -rp "Login : " server["mp_login"]
read -rp "Password : " server["mp_password"]
# Select Titlepack
echo ""
PS3="
Select an option [1-${#TMMNG_TITLEPACKS[@]}] : "
select entry in "${TMMNG_TITLEPACKS[@]}"; do
if contains_element "${entry}" "${TMMNG_TITLEPACKS[@]}"; then
    server["titlepack"]="${entry}"
    break
else
    echo "Invalid choice"
fi
done
# Server Title
read -rp "Server name [My nice TM server] : " server["name"]
echo "Server comment [This is a comment for my nice TM server] :"
read -r server["comment"]
} #}}}

function deploy_server() { #Parameters -- 1:(str) version {{{
local version="${1:-Latest}"
# TODO Print message server deploy ongoing.

unzip -o "${TMMNG_RESOURCES_DIR}/servers/ManiaplanetServer_${version}.zip" \
-d "${SERVERS_ROOT_DIRECTORY}/${server['id']}" > /dev/null 2>&1
# TODO Checks

# Copy config & edit
cp "${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Config/dedicated_cfg.default.txt" \
"${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Config/dedicated_cfg.txt"


#printf '%s' "$(awk "/<${section}>/,/<\/${section_close}>/" "${l_config_file}" | grep "<${id}>" | awk -F "</?${id}>" '{ print $2  }')"



for key in ${TMMNG_INST_KEYS_STRUCT['keys']}; do
    sed -i -e "/<${TMMNG_INST_KEYS_STRUCT["${key},section"]}>/,/<\/${TMMNG_INST_KEYS_STRUCT["${key},section"]}>/\
{s/<${TMMNG_INST_KEYS_STRUCT["${key},tag"]}>${TMMNG_INST_KEYS_STRUCT["${key},tag_def"]}<\/${TMMNG_INST_KEYS_STRUCT["${key},tag"]}>/\
<${TMMNG_INST_KEYS_STRUCT["${key},tag"]}>${server["${key}"]}<\/${TMMNG_INST_KEYS_STRUCT["${key},tag"]}>/}" \
"${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Config/dedicated_cfg.txt"
done

# Copy titlepack
cp "${TMMNG_RESOURCES_DIR}/titlepacks/${server['titlepack']}.Title.Pack.gbx.latest" \
"${SERVERS_ROOT_DIRECTORY}/${server['id']}/Packs/${server['titlepack']}.Title.Pack.gbx"

# Copy Maps and tracklist
local default_map=""
mkdir -p "${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/"{Defaults,MatchSettings}
cp "${TMMNG_RESOURCES_DIR}/maps/tracklist.txt" \
"${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/MatchSettings/tracklist.txt"
case "${server['titlepack']}" in
    "TMStadium@nadeo" | "esl_comp@lt_forever")
        cp "${TMMNG_RESOURCES_DIR}/maps/A01.Map.Gbx.TMStadium" \
        "${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/Defaults/A01.Map.Gbx"
        default_map="Defaults\/A01.Map.Gbx"
        ;;
    "TMCanyon@nadeo")
        cp "${TMMNG_RESOURCES_DIR}/maps/A01.Map.Gbx.TMCanyon" \
        "${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/Defaults/A01.Map.Gbx"
        default_map="Defaults\/A01.Map.Gbx"
        ;;
    "RPG@tmrpg")
        cp "${TMMNG_RESOURCES_DIR}/maps/RPG_Nos_Astra.Map.Gbx" \
        "${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/Defaults/RPG_Nos_Astra.Map.Gbx"
        default_map="Defaults\/RPG_Nos_Astra.Map.Gbx"
        ;;
esac

sed -i -e "s/<title>titlepack<\/title>/<title>${server['titlepack']}<\/title>/" \
"${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/MatchSettings/tracklist.txt"

sed -i -e "s/<file>DEFAULT_MAP<\/file>/<file>${default_map}<\/file>/" \
"${SERVERS_ROOT_DIRECTORY}/${server['id']}/UserData/Maps/MatchSettings/tracklist.txt"

require_module "controllers"
for controller in ${server['controller']}; do
    init_controller_server "${controller}"
done

#Update config file
#shellcheck disable=SC2154
if ! grep "\[list\]=.*${server['id']}.*" "${manager_config_file}" > /dev/null 2>&1; then
    sed -i "/\[list\]=\".*\"/s/\"$/ ${server['id']}\"/" "${manager_config_file}"
fi

if ! grep "\[${server['id']},controller\]=" "${manager_config_file}" > /dev/null 2>&1; then
    sed -i "/^) # DO NOT MODIFY THIS LINE/i \[${server['id']},controller\]=\"${server['controller']}\"" "${manager_config_file}"
elif grep "\[${server['id']},controller\]=\"${server['controller']}\"" "${manager_config_file}" > /dev/null 2>&1; then
    #Do nothing all is good
    :
else
    # Replace
    sed -i "s/\[${server['id']},controller\]=.*$/\[${server['id']},controller\]=\"${server['controller']}\"/" "${manager_config_file}"
fi
} #}}}

#shellcheck disable=SC2034
declare -gr MOD_SERVER_INSTALL_LOADED=true
