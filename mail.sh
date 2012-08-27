#!/bin/bash
############################################################
#
# This script automates mail bounce back handling on EPLAPP.
# Author:   Andrew Nisbet, anisbet@epl.ca
# Date:     August 27, 2012
# Version:  0.1
#
############################################################

perl ./parsemail.pl -c
perl ./bounceback.pl -u
# Should produce nothing
tail userkeys.lst | dumpflatuser | grep EMAIL
if [ $? ] then;
	echo "problem: email address not deleted."
fi
tail userkeys.lst | dumpflatuser | grep NOTE
