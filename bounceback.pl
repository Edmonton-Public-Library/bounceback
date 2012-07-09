#!/usr/bin/perl -w
########################################################################
# Purpose: Updates users' accounts that their emails don't work.
# Method:  Initially read a list of emails, find them in the BSR and 
#          delete the VED record of their email and create a note that
#          Email bounced: [address]. [reason] [date]
#          in the note field of the extended data section of their account.
#
# Author:  Andrew Nisbet, Edmonton Public Library.
# Date:    July 9, 2012
# Rev:     0.0 - July 9, 2012 Develop
########################################################################

use strict;
use warnings;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
$ENV{'PATH'} = ":/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/s/sirsi/Unicorn/Search/Bin";
$ENV{'UPATH'} = "/s/sirsi/Unicorn/Config/upath";
###############################################

my $date    = `transdate -d-0`;
chomp($date);

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-u]
	
Handles the arduous task of updating users accounts if their emails don't work.

 -u : Actually update the records, don't just show me what you're doing.
 -x : This (help) message.

example: echo email_addresses.lst | $0 -u

EOF
    exit;
}

my $searchString;
my $inputFile;

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'ux';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
}
init();

my @emailList = ();
@emailList = <STDIN>;
foreach my $email (@emailList)
{
	chomp($email);
	my $results = `echo "$email {EMAI}" | selusertext`;
	if ( $results ) #my $message = "Email bounced: s.sabri@shaw.ca. Undeliverable 20120709";
	{
		print "email: $email =>$results<=";
	}
}
1;