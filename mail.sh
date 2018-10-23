#!/bin/bash
###############################################################################
#
# This script automates mail bounce back handling on EPLAPP.
#
#    Copyright (C) 2018  Andrew Nisbet, Edmonton Public Library
# The Edmonton Public Library respectfully acknowledges that we sit on
# Treaty 6 territory, traditional lands of First Nations and Metis people.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
# MA 02110-1301, USA.
#
# Author:   Andrew Nisbet, anisbet@epl.ca
# Date:     August 27, 2012
# Version:  0.2 Use this instead of Makefiles. This will make cron-able.
#           0.1
#
###############################################################################
source /s/sirsi/Unicorn/EPLwork/cronjobscripts/setscriptenvironment.sh
MAIL_DIR=/s/sirsi/Unicorn/EPLwork/anisbet/Mail
perl $MAIL_DIR/parsemail.pl -c
perl $MAIL_DIR/bounceback.pl -u
# EOF
