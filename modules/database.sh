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

declare -ga DATABASE_ERROR_MESSAGES=(
"Runtime error"
"Database credential are not set in config file"
)

declare -g DATABASE_HOST="${DATABASE_HOST:-localhost}"
declare -g DATABASE_USER="${DATABASE_USER:?$(exit_handler 1 DATABASE_ERROR_MESSAGES)}"
declare -g DATABASE_PASSWORD="${DATABASE_PASSWORD:?$(exit_handler 1 DATABASE_ERROR_MESSAGES)}"

declare -gr MOD_DATABASE_LOADED=true
