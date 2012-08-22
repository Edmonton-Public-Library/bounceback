#!/usr/bin/perl -w
########################################################################
# Purpose: Parses the /var/mail/sirsi file making note of accounts that 
#          have bounced and reporting strange trends like getting too
#          many bouncebacks which might indicate we have been blacklisted.
# Method:  Open /var/mail/sirsi, look for error notice in header, write 
#          explaination and address to file. Keep track of stats and
#          report them, including total bounced by reason.
#
# Author:  Andrew Nisbet, Edmonton Public Library.
# Date:    July 13, 2012
# Rev:     0.0 - July 13, 2012 Develop
########################################################################
use strict;
use vars qw/ %opt /;
use Getopt::Std;

# Environment setup required by cron to run script because its daemon runs
# without assuming any environment settings and we need to use sirsi's.
###############################################
# *** Edit these to suit your environment *** #
# $ENV{'PATH'} = ":/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/s/sirsi/Unicorn/Search/Bin";
# $ENV{'UPATH'} = "/s/sirsi/Unicorn/Config/upath";
###############################################

my $noteHeader       = "Undeliverable email address"; # append "[address]. [Reason for bounceback.][date]" later as we figure them out.
my $mailbox          = "/var/mail/sirsi";
my $bouncedCustomers = "./NDR.log";
my $warningLimit     = 200; # limit beyond which a warning is issued that we are getting too many bounced emails.
my $stakeholders     = qq{ilsteam\@epl.ca}; # list of parties interested in the amount of bounced email.

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-c][-d]
	
Handles the arduous task of updating users accounts if their emails don't work.

 -d : Diagnostics.
 -c : Clean /var/mail/sirsi file.
 -x : This (help) message.

example: $0

EOF
    exit;
}

# Returns a timestamp for the log file only. The Database uses the default
# time of writing the record for its timestamp in SQL. That was done to avoid
# the snarl of differences between MySQL and Perl timestamp details.
# Return: string of the current date and time as: 'yyyy-mm-dd hh:mm:ss'
sub getDate
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)=localtime(time);
	$year += 1900;
	$mon  += 1;
	if ($mon < 10)
	{
		$mon = "0$mon";
	}
	if ($mday < 10)
	{
		$mday = "0$mday";
	}
	my $date = "$year-$mon-$mday";
	return $date;
}

#
# Trim function to remove whitespace from the start and end of the string.
# param:  string to trim.
# return: string without leading or trailing spaces.
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'dcx';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
	if (not -s $mailbox) # file not exist or has zero size
	{
		print getDate()." no mail to process.\n";
		exit 1;
	}
}

init();
open SIRSI_MAIL, "<$mailbox" or die "Error opening $mailbox: $!\n";
open BOUNCED_CUSTOMERS, ">>$bouncedCustomers" or die "Error opening $bouncedCustomers: $!\n";
print BOUNCED_CUSTOMERS "\n".getDate()."\n";
my $emailAddress = "";
my %reasonCount;
my %domainCount;
my $customerEmailCount = 0;
my %uniquePatronEmails;
while (<SIRSI_MAIL>)
{
	# look for the header 
	# Final-Recipient: RFC822; razzak_syad@hotmail.com
	# Action: failed
	# The syntax for the action-field is:
	# action-field = "Action" ":" action-value
	# action-value =
	# "failed" / "delayed" / "delivered" / "relayed" / "expanded"
	# The action-value may be spelled in any combination of upper and lower
	# case characters.
	# Moore & Vaudreuil           Standards Track                    [Page 16]
	# RFC 3464             Delivery Status Notifications          January 2003
	# "failed"    indicates that the message could not be delivered to the
    # recipient.  The Reporting MTA has abandoned any attempts
	# to deliver the message to this recipient.  No further
	# notifications should be expected.
	if ( $_ =~ m/^Action:/ )
	{
		my @actionReason = split( ':', $_ );
		my $reason = lc ( trim( $actionReason[1] ) );
		$reasonCount{ $reason } = 0 if ( not $reasonCount{ $reason } );
		$reasonCount{ $reason }++;
		if ( $reason =~ m/failed/i )
		{
			# some emails come back with angle brackets.
			$emailAddress =~ s/[<>]//g;
			if ( not $uniquePatronEmails{ $emailAddress } )
			{
				$uniquePatronEmails{ $emailAddress } = 1;
				print BOUNCED_CUSTOMERS "$noteHeader|$emailAddress\n";
			}
		}
	}
	# capture every Final-Recipient for statistics reporting.
	if ( $_ =~ m/^Final-Recipient:/ )
	{
		# snag the address while we can, if Action turns out to be failed then we will use it.
		my @finalRecipientAddress = split( ';', $_ );
		$emailAddress = trim( $finalRecipientAddress[1] );
		my @nameDomain = split( '\@', $emailAddress );
		my $domain = lc( $nameDomain[1] );
		$domainCount{ $domain } = 0 if ( not $domainCount{ $domain } );
		$domainCount{ $domain }++;
	}
}
$customerEmailCount = scalar(keys(%uniquePatronEmails));
close BOUNCED_CUSTOMERS;
close SIRSI_MAIL;

# mail stats to andrew.
my ($k, $v);
my $mail = "";
while( ($k, $v) = each %reasonCount ) 
{
	$mail .= "$k: $v.\n";
	print "$k: $v.\n";
}


#
# Compose email report.
#
if ( $customerEmailCount > $warningLimit )
{
	open( MAIL, "| /usr/bin/mailx -s 'Problem: Email report' $stakeholders" ) || warn "mailx failed: $!\n";
    print MAIL "There may be a problem with emails from EPLAPP. $customerEmailCount emails have bounced. Check NDR.log for more details.\n";
	print MAIL "$mail\n";
	close( MAIL );
}
elsif ( $customerEmailCount == 0 )
{
	open( MAIL, "| /usr/bin/mailx -s 'No bounced email to report' $stakeholders" ) || warn "mailx failed: $!\n";
	print MAIL "There are no bounced messages.\n";
	close( MAIL );
}
else
{
	open( MAIL, "| /usr/bin/mailx -s 'Email report' $stakeholders" ) || warn "mailx failed: $!\n";
	print MAIL "$mail\n";
	close( MAIL );
}

# Diagnostics
if ( $opt{'d'} )
{
	print "Domains:\n";
	format STATS =
@<<<<<<<<<<<<<<<<<<<<<< @####
$k, $v
.
	$~ = "STATS";
	while( ($k, $v) = ( each %domainCount ) )
	{
		write;
	}
}

# c - clean the mail file? (Why would you?)
if ( $opt{'c'} )
{
	unlink($mailbox);
}
1;