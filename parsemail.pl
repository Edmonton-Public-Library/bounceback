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
$ENV{'PATH'} = ":/s/sirsi/Unicorn/Bincustom:/s/sirsi/Unicorn/Bin:/s/sirsi/Unicorn/Search/Bin";
$ENV{'UPATH'} = "/s/sirsi/Unicorn/Config/upath";
###############################################

my $noteHeader       = "Undeliverable email address"; # append "[address]. [Reason for bounceback.][date]" later as we figure them out.
my $mailbox          = "/var/mail/sirsi";
my $bouncedCustomers = "./NDR.log";
my $warningLimit     = 200; # limit beyond which a warning is issued that we are getting too many bounced emails.

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-c][-d]
	
Handles the arduous task of updating users accounts if their emails don't work.

 -d : Diagnostics.
 -c : Clean the /var/mail/sirsi file.
 -x : This (help) message.

example: $0

EOF
    exit;
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
		print "No mail to process.\n";
		exit 1;
	}
}

init();
open SIRSI_MAIL, "<$mailbox" or die "Error opening $mailbox: $!\n";
open BOUNCED_CUSTOMERS, ">>$bouncedCustomers" or die "Error opening $bouncedCustomers: $!\n";
my $S_RECIPIENT = 1;
my $S_NONE      = 0;
my $state       = $S_NONE;
my $emailAddress;
my %reasonCount;
my %domainCount;
my $customerEmailCount;
while (<SIRSI_MAIL>)
{
	# look for the header 
	# Final-Recipient: RFC822; xyz@hotmail.com
	# Action: failed
	if ( $_ =~ m/^Action:/ and $state == $S_RECIPIENT )
	{
		my @actionReason = split(':', $_);
		my $reason = lc ( trim( $actionReason[1] ) );
		$reasonCount{ $reason } = 0 if ( not $reasonCount{ $reason } );
		$reasonCount{ $reason }++;
		$state = $S_NONE;
	}
	if ( $_ =~ m/^Final-Recipient:/ )
	{
		$state = $S_RECIPIENT;
		my @finalRecipientAddress = split( ';', $_ );
		$emailAddress = trim( $finalRecipientAddress[1] );
		print BOUNCED_CUSTOMERS "$noteHeader|$emailAddress\n";
		$customerEmailCount++;
		my @nameDomain = split( '\@', $emailAddress );
		my $domain = lc( $nameDomain[1] );
		$domainCount{ $domain } = 0 if ( not $domainCount{ $domain } );
		$domainCount{ $domain }++;
	}
}

close BOUNCED_CUSTOMERS;
close SIRSI_MAIL;

# mail stats to andrew.
my ($k, $v);
my $mail = "Reasons:\n";
while( ($k, $v) = each %reasonCount ) 
{
	$mail .= "$k: $v.\n";
	print "$k: $v.\n";
}
# Mail results.
open( MAIL, "| /usr/bin/mailx -s 'Email report' ilsteam\@epl.ca" ) || warn "mailx failed: $!\n";
if ( $customerEmailCount > $warningLimit )
{
    print MAIL "There may be a problem with emails from EPLAPP. $customerEmailCount emails have bounced. Check NDR.log for more details.\n";
}
print MAIL "$mail\n";
close( MAIL );

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

# Keep the mail? (Why would you?)
if ( $opt{'c'} )
{
	unlink($mailbox);
}
1;