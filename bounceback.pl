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
# Rev:     0.2 - August 23, 2012 Initial release
########################################################################
# TODO: there is a '.forward' file that is sending all this stuff to ILS Notices. We should remove that so the mail ends up in /var/mail/sirsi and process mail from there. then we don't have to worry about spam et al.
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
my $ndr        = "NDR.log";
my $date       = `transdate -d-0`;
chomp($date);

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-u][-d<n>]
	
Handles the arduous task of updating users accounts if their emails don't work.

 -d int : Debug 'n' number of emails.
 -u     : Actually update the records, don't just show me what you're doing.
 -x     : This (help) message.

example: $0 -u

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
open PREUPDATEPATRON, ">>patron.flat" or die "Error opening backup flat user: $!\n";
my $logDate;
open NDR_LOG, "<$ndr" or die "Exiting. No list of patrons emails to process.\n";
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
open USER_KEYS, ">>userkeys.lst" or die "Can't save user keys: $!\n";
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
	# Split log file into reason and address.
	my ($bounceReason, $email) = split('\|', $NDRlogRecord);
	if (not $email)
	{
		print     "no email found in '$NDRlogRecord'\n";
		print LOG "no email found in '$NDRlogRecord'\n";
		next;
	}
	print "--($bounceReason, $email)--\n" if ($opt{'d'});
	print LOG "--($bounceReason, $email)--\n";
	# get the VED fields for this user via API.
	my $userKey = `echo "$email {EMAIL}"|selusertext|seluser -iU -oU -p"~LOSTCARD,MISSING,EPL-CANCEL,DISCARD"`;
	if ( not $userKey )
	{
		print LOG "user key $userKey has a profile of either LOSTCARD,MISSING,EPL-CANCEL,DISCARD and will not be processed.\n";
		next;
	}
	print USER_KEYS "$userKey";
	print  "$userKey";
	my $flatUser = `echo "$userKey" | dumpflatuser`;
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
		if ($opt{'d'})
		{
			open(BEFORE, ">beforeVED.txt") or die "Error: $!\n";
			print BEFORE "$flatUser";
			close(BEFORE);
		}
		my $noteField = $noteHeader . " '$email'. $bounceReason. $logDate";
		my @VEDFields = split('\n', $flatUser);
		@VEDFields = updateNoteVED($noteField, @VEDFields);
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
		print "$flatUser";
		# -aR replace address fields, -bR replace extended fields, -mu just update user never create, -n don't reference BRS
		# This switch is necessary so that the loadflatuser doesn't check for ACTIVE_IDs for the customer, then failing if they
		# have them. -n does create an entry in /s/sirsi/Unicorn/Database/Useredit, so touchkeys is not required.
		`echo "$flatUser" | loadflatuser -aR -bR -l"ADMIN|PCGUI-DISP" -mu -n`;
		print LOG "User updated.\n";
	}
	# Exit early when debugging.
	last if ($opt{'d'} and $debugCounter == $opt{'d'});
	$debugCounter++;
}
close(USER_KEYS);
print LOG "removing $ndr\n";
unlink($ndr);
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
sub updateNoteVED
{
	my ( $newValue, @VEDFields ) = @_;
	my @newVED = ();
	chomp( $newValue );
	while ( @VEDFields )
	{
		my $VEDField = shift( @VEDFields );
		if ( $VEDField =~ m/^\.USER_XINFO_BEGIN\./ )
		{
			push( @newVED, $VEDField );
			push( @newVED, ".NOTE. |a$newValue" );
			print     "Appended: '$newValue'\n" if ($opt{'d'});
			print LOG "Appended: '$newValue'\n";
		}
		else
		{
			push(@newVED, $VEDField);
		}
	}
	return @newVED;
}