#!/bin/sh

declare -r maniacontrol_scriptlocation="$( cd "$( dirname "${BASH_SOURCE[0]}"  )" && pwd  )"

declare maniacontrol_php_main="${1:?Cannot run Maniacontrol error in arg1}"
declare maniacontrol_config_file="${2:?Cannot run Maniacontrol error in arg2}"
declare maniacontrol_server_id="${3:?Cannot run Maniacontrol error in arg3}"
declare maniacontrol_log_dir="${4:?Cannot run Maniacontrol error in arg4}"
declare maniacontrol_pid_file="${5:?Cannot run Maniacontrol error in arg5}"

php "${maniacontrol_php_main}" -config="${maniacontrol_config_file}" -id="${maniacontrol_server_id}" -sh "${0} ${maniacontrol_php_main} ${maniacontrol_config_file} ${maniacontrol_server_id} ${maniacontrol_log_dir} ${maniacontrol_pid_file}"> "${maniacontrol_log_dir}/ManiaControl_${maniacontrol_server_id}_$(date +%Y%m%d_%H%M).log" 2>&1 &
pid=$!
printf '%d' "${pid}" > "${maniacontrol_pid_file}"
