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
open LOG, ">>bounceback.log" or die "Error opening log file: $!\n";
open PREUPDATEPATRON, ">>patron-flatuser.bck" or die "Error opening backup flat user: $!\n";
my $logDate;
open NDR_LOG, "<NDR.log" or die "Error opening NDR.log: $!\n";
my @emailList = <NDR_LOG>;
close(NDR_LOG);
if (@emailList > 200)
{
	print "* Warning: there seems to be a large number of bounced emails (" . scalar(@emailList) . "). Are you being black-listed by an ISP? *\n";
	print "* Warning: if you are you don't want to alter some of these customer's accounts *\nDo you want to continue <yes|no> ";
	my $answer;
	chomp ($answer = <>);
	if ($answer !~ m/^y/i)
	{
		print "that's probably a good idea. exiting.\n";
		exit 0;
	}
}
# advance this counter for every iteration of a client so the script will
# exit when the count reaches the values specifed with the -d flag.
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
		print "Processed on $logDate\n" if ($opt{'d'});
		print LOG "Processed on $logDate\n";
		next;
	}
	# Split Jamie's log file into reason and address.
	my ($bounceReason, $email) = split('\|', $NDRlogRecord);
	if (not $email)
	{
		print "no email found in '$NDRlogRecord'\n";
		next;
	}
	print "--($bounceReason, $email)--\n" if ($opt{'d'});
	print LOG "--($bounceReason, $email)--\n";
	# get the VED fields for this user via API.
	my $flatUser = `echo "$email {EMAIL}"|selusertext|dumpflatuser`;
	if ( not $flatUser ) #my $message = "Email bounced: s.sabri@shaw.ca. Undeliverable 20120709";
	{
		print     "no patron found with email of '$email'.\n";
		print LOG "no patron found with email of '$email'.\n";
		next;
	}
	
	# Update the user's account. Now it turns out that on the recommendation of Margaret Pelfrey 
	# you need get the entire record from dumpflatuser, modify the contents, and overlay the record
	# over the original.
	if ($opt{'u'})
	{
		# we save the original record for our records in case.
		print PREUPDATEPATRON "$flatUser";
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
		# reload the user Replace address field, Replace extended information but DON'T create user if they don't exist.
		`echo "$flatUser" | loadflatuser -aR -bR -l"ADMIN|PCGUI-DISP" -mu`;
		print LOG "User updated.\n";
	}
	# Exit early when debugging.
	exit if ($opt{'d'} and $debugCounter == $opt{'d'});
	$debugCounter++;
}
close(LOG);
close(PREUPDATEPATRON);
1;

# Deletes a single VED record.
# param:  field string - name of the VED record to delete, like 'EMAIL'. Do not include the '.' at the beginning or
#         or end of the field name. The field must start with the argument name exactly - case matters.
# return: List - argument list returned with the specified VED record removed.
sub deleteVED
{
	my ($field, @VEDFields) = @_;
	my @newVED = ();
	while (@VEDFields)
	{
		my $VEDField = shift(@VEDFields);
		if ($VEDField =~ m/^\.($field)\./)
		{
			print     "DELETE: $VEDField\n\n" if ($opt{'d'});
			print LOG "DELETED: $VEDField\n";
			next;
		}
		push(@newVED, $VEDField);
	}
	
	return @newVED;
}

# Appends value to an existing VED record if one exists.
# param:  field string - name of the VED record to append to, like 'NOTE'. Do not include the '.' at the beginning or
#         or end of the field name. The field must start with the argument name exactly - case sensitive.
# return: List - argument list returned with the specified VED record updated.
sub appendVED
{
	my ($field, $newValue, @VEDFields) = @_;
	my @newVED = ();
	chomp($newValue);
	while (@VEDFields)
	{
		my $VEDField = shift(@VEDFields);
		if ($VEDField =~ m/^\.($field)\./)
		{
			chomp($VEDField);
			print "==$VEDField==\n" if ($opt{'d'});
			my $tmp = shift(@VEDFields);
			while ($tmp !~ m/^\./)
			{
				$VEDField .= $tmp;
				chomp($VEDField);
				$tmp = shift(@VEDFields);
			}
			# now append the new content
			$VEDField .= " ".$newValue;
			push(@newVED, $VEDField);
			# now put back the last shifted value that tested positive for another field marker.
			push(@newVED, $tmp);
			print     "APPEND: $VEDField\n" if ($opt{'d'});
			print LOG "APPEND: $VEDField\n";
		}
		else
		{
			push(@newVED, $VEDField);
		}
	}
	return @newVED;
}