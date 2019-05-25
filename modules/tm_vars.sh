#!/bin/bash
#shellcheck disable=SC2034

###############################################################################
#Variables used by the trackmania manager
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

declare -g TMMNG_RESOURCES_DIR="${TMMNG_RESOURCES_DIR:-${SCRIPT_LOCATION}/resources}"
declare -ga TMMNG_TITLEPACKS=("TMStadium@nadeo" "TMCanyon@nadeo" "esl_comp@lt_forever" "RPG@tmrpg")

declare -gr MOD_TM_VARS_LOADED=true
