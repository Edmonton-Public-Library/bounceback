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

	usage: cat NDR.log | $0 [-x][-u]
	
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
	chomp($NDRlogRecord);
	# There is an empty line.
	next if ( not $NDRlogRecord or $NDRlogRecord eq "" );
	# There is an entry that is a date field.
	if($NDRlogRecord =~ m/^\d/)
	{
		$logDate = $NDRlogRecord;
		print ">>Processed on $logDate<<\n" if ($opt{'d'});
		next;
	}
	# Split Jamie's log file into reason and address.
	my ($bounceReason, $email) = split('\|', $NDRlogRecord);
	if (not $email)
	{
		print "no email found in '$NDRlogRecord'\n";
		next;
	}
	print ">>>($bounceReason, $email)<<<\n" if ($opt{'d'});
	# get the VED fields for this user via API.
	my $flatUser = `echo "$email {EMAIL}"|selusertext|dumpflatuser`;
	if ( not $flatUser ) #my $message = "Email bounced: s.sabri@shaw.ca. Undeliverable 20120709";
	{
		print "ignoring empty result from seluser.\n";
		next;
	}
	
	if ($opt{'u'})
	{
		# now everything is set we have to do the following:
		# 1) zero out the email. Now we have to remove the record not just empty it. There is a script that runs to clean empty email enties(?).
		# `echo "$barCode||" | edituserved -b -eEMAIL -l"ADMIN|PCGUI-DISP" -t1`;
		# 2) edit the note field to include previous notes and the requested message.
		my $noteField = $noteHeader . " '$email'. $bounceReason. $logDate";
		if ($opt{'d'})
		{
			open(BEFORE, ">beforeVED.txt") or die "Error: $!\n";
			print BEFORE "$flatUser";
			close(BEFORE);
		}
		my @VEDFields = split('\n', $flatUser);
		@VEDFields = appendVED("NOTE", $noteField, @VEDFields);
		@VEDFields = deleteVED("EMAIL", @VEDFields);
		$flatUser  = "";
		foreach (@VEDFields)
		{
			$flatUser .= $_."\n";
		}
		if ($opt{'d'})
		{
			open(AFTER, ">afterVED.txt") or die "Error: $!\n";
			print AFTER "$flatUser";
			close(AFTER);
		}
	}
	exit if ($opt{'d'} and $debugCounter == $opt{'d'});
	$debugCounter++;
}
1;

sub deleteVED
{
	my ($field, @VEDFields) = @_;
	my $vedIndex = 0;
	my $atIndex  = -1;
	foreach my $VEDField (@VEDFields)
	{
		# print "$VEDField\n";
		if ($VEDField =~ m/^\.($field)\./)
		{
			print "DELETE: $VEDField\n\n" if ($opt{'d'});
			$atIndex = $vedIndex;
			last;
		}
		$vedIndex++;
	}
	# don't delete anything if we didn't find the field we are after.
	# you have to be careful not to delete an element in an array during
	if ($atIndex > -1)
	{
		# use splice because delete doesn't delete the element it just deletes the elements contents.
		splice(@VEDFields, $atIndex, 1);
	}
	return @VEDFields;
}

sub appendVED
{
	my ($field, $newValue, @VEDFields) = @_;
	foreach my $VEDField (@VEDFields)
	{
		# print "$VEDField\n";
		if ($VEDField =~ m/^\.($field)\./)
		{
			$VEDField .= " ".$newValue;
			print "APPEND: $VEDField\n";
		}
	}
	return @VEDFields;
}