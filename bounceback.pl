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

my $noteHeader = "Email bounced:"; # append "[address]. [Reason for bounceback.][date]" later as we figure them out.
my $date = `transdate -d-0`;
chomp($date);

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-u]
	
Handles the arduous task of updating users accounts if their emails don't work.

 -d int : Debug 'n' number of emails.
 -u     : Actually update the records, don't just show me what you're doing.
 -x     : This (help) message.

example: echo email_addresses.lst | $0 -u

EOF
    exit;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'uxd:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
}

init();

my $logDate;
my @emailList = ();
@emailList = <STDIN>;
my $debugCounter = 0;
foreach my $NDRlogRecord (@emailList)
{
	#chomp($NDRlogRecord);
	# There is an empty line.
	next if ( not $NDRlogRecord or $NDRlogRecord eq "" );
	# There is an entry that is a date field.
	if($NDRlogRecord =~ m/^\d/)
	{
		chomp( $logDate = $NDRlogRecord );
		print ">Processed on $logDate\n" if ($opt{'d'});
		next;
	}
	my ($bounceReason, $email) = split('\|', $NDRlogRecord);
	chomp($email);
	print ">>>($bounceReason, $email)\n" if ($opt{'d'});
	my $results = `echo "$email {EMAIL}"|selusertext|seluser -iU -oUBV.9998.V.9007.`;
	if ( not $results ) #my $message = "Email bounced: s.sabri@shaw.ca. Undeliverable 20120709";
	{
		print "ignoring empty result from seluser.\n";
		next;
	}
	# produces:
	# 214XXX|2122101814XXXX||joxxxx@artktecture.ca|
	my ($userKey, $barCode, $note, $vedEmail) = split('\|', $results);
	print ">>>'$userKey', '$barCode', '$note', '$email'\n" if ($opt{'d'});
	# if everything went well you should have the minimum of a key, barcode and email.
	if (not $userKey or not $barCode or not $vedEmail)
	{
		print "patron could not be found by '$email'.\n";
		next;
	}
	if ($opt{'u'})
	{
		# now everything is set we have to do the following:
		# 1) zero out the email. Now we have to remove the record not just empty it. There is a script that runs to clean empty email enties(?).
		# `echo "$barCode||" | edituserved -b -eEMAIL -l"ADMIN|PCGUI-DISP" -t1`;
		# 2) edit the note field to include previous notes and the requested message.
		my $noteField = qq{$note$noteHeader '$email'. $bounceReason $logDate};
		print "$noteField" if ($opt{'d'});
		# `echo "$barCode|$noteField|" | edituserved -b -eNOTE -l"ADMIN|PCGUI-DISP" -tx`;
		# TODO test this with a file that contains one email or use -d 1 and see what it does to the VED.
	}
	exit if ($opt{'d'} and $debugCounter == $opt{'d'});
	$debugCounter++;
}
1;