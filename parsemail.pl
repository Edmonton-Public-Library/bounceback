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
# Rev:     0.2 - August 23, 2012 Develop
########################################################################
use strict;
use vars qw/ %opt /;
use Getopt::Std;

my $mailFile         = "mail.txt";
my $noteHeader       = ""; # append "[address]. [Reason for bounceback.][date]" later as we figure them out.
my $mailbox          = "/var/mail/sirsi";
my $bouncedCustomers = "./NDR.log";
my $warningLimit     = 100; # limit beyond which a warning is issued that we are getting too many bounced emails.
my $stakeholders     = qq{ilsteam\@epl.ca}; # list of parties interested in the amount of bounced email.
my $dierWarningSent  = 0; # if 0 no message sent yet, if true then suppress additional warnings about blacklisting.

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-c]
	
Handles the arduous task of updating users accounts if their emails don't work.

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
	if ( -s $bouncedCustomers )
	{
		print "'$bouncedCustomers' exists.\nYesterday's list may not have been processed. Do you want to over write it? <yes|no> ";
		my $answer;
		chomp ($answer = <>);
		if ($answer !~ m/^y/i)
		{
			print "exiting.\n";
			exit 0;
		}
	}
}

#
# Sends recipients messages via email.
# param:  subject string
# param:  recipents emails string
# param:  message string
# return:
#
sub sendMail
{
	my ($subject, $recipients, $message) = @_;
	open( MAILER, "| /usr/bin/mailx -s '$subject' $recipients" ) or warn "Unable to send mail report because: $!\n";
	print MAILER "$message\n\nSigned: parsemail.pl on EPLAPP\n";
	close( MAILER );
}

init();
open SIRSI_MAIL, "<$mailbox" or die "Error opening $mailbox: $!\n";
open BOUNCED_CUSTOMERS, ">$bouncedCustomers" or die "Error opening $bouncedCustomers: $!\n";
print BOUNCED_CUSTOMERS "\n".getDate()."\n";
my $emailAddress    = "";
my %rejectionNotice = ();
$rejectionNotice{ 571 } = qq{EPL has been blacklisted by recipients domain};
$rejectionNotice{ 450 } = qq{Patron's mailbox is unreachable and may be corrupted, offline indefinitely, or EPL blacklisted by domain};
$rejectionNotice{ 554 } = qq{Recipient's server believes EPL's email is spam};
$rejectionNotice{ 553 } = qq{Mailbox address is invalid};
$rejectionNotice{ 551 } = qq{Relay denied, recipient's ISP needs to allow EPL};
$rejectionNotice{ 550 } = qq{Patron's Mailbox is either disabled, suspended, firewall-blocking EPL, or does not exist};
$rejectionNotice{ 541 } = qq{Patron's firewall has rejected EPL's mail};
$rejectionNotice{ 521 } = qq{Patron's email account is disabled};
$rejectionNotice{ 513 } = qq{Recipient's mail server thinks the address is incorrectly formatted. Check for invalid characters};
$rejectionNotice{ 512 } = qq{The host server for the recipient’s domain name cannot be found};
$rejectionNotice{ 510 } = qq{Bad email address. Confirm spelling};
$rejectionNotice{ 511 } = qq{Bad email address. Confirm spelling};
$rejectionNotice{ 422 } = qq{Patron's mail box is full};
$rejectionNotice{ 552 } = qq{Mail aborted because mailbox is full};
$rejectionNotice{ 111 } = qq{Patron's mail server refused our connection request};

my %reasonCount;
my %domainCount;
my $customerEmailCount = 0;
my %uniquePatronEmails;
# Email header ordering:
# Arrival-Date: Tue, 28 Aug 2012 05:18:37 -0700
# Final-Recipient: rfc822;news.hotmail8@gmail.com
# Action: failed
# Status: 5.2.1
# Diagnostic-Code: smtp;550 5.2.1 The email account that you tried to reach is disabled. c16si8407304anl.34
while (<SIRSI_MAIL>)
{
	# capture every Final-Recipient for statistics reporting.
	if ( $_ =~ m/^Final-Recipient:/i )
	{
		# snag the address while we can, if Action turns out to be failed then we will use it.
		my @finalRecipientAddress = split( ';', $_ );
		$emailAddress = trim( $finalRecipientAddress[1] );
		# some emails come back with angle brackets.
		$emailAddress =~ s/[<>]//g;
		my @nameDomain = split( '\@', $emailAddress );
		my $domain = lc( $nameDomain[1] );
		$domainCount{ $domain }++;
	}
	if ( $_ =~ m/^Status:/i )
	{
		my @statusReason = split( ':', $_ );
		$statusReason[1] =~ s/\.//g;
		$statusReason[1] =~ s/^\s+//g;
		my $status = substr($statusReason[1], 0, 3);
		# print "---->$status<-----\n";
		if ( $rejectionNotice{ $status } )
		{
			# here we send an early warning message if the status is about being blacklisted.
			if ( $status == 571 )
			{
				if ( not $dierWarningSent )
				{
					my $msg = "A patron's email ($emailAddress) was returned because we was blacklisted, please investigate.";
					sendMail( "***Blacklist Warning***", "anisbet\@epl.ca", $msg );
				}
				$dierWarningSent++;
			}
			else # User specific bounce problem
			{
				$noteHeader = $rejectionNotice{ $status };
				# don't add address if this is the second message that bounced.
				if ( not $uniquePatronEmails{ $emailAddress } )
				{
					$uniquePatronEmails{ $emailAddress } = 1;
					print BOUNCED_CUSTOMERS "$noteHeader|$emailAddress\n";
				}
			}
			$reasonCount{ $rejectionNotice{ $status } }++;
		}
		else # unknown probably harmless status was found. Don't edit patron account.
		{
			$reasonCount{ $status }++;
		}
	}
}
$customerEmailCount = scalar( keys( %uniquePatronEmails ) );
close BOUNCED_CUSTOMERS;
close SIRSI_MAIL;

# c - clean the mail file? (Why would you?)
if ( $opt{'c'} )
{
	unlink($mailbox);
}

#
# Compose email report.
#
open( MAIL, ">$mailFile" ) or die "Unable to send mail report because: $!\n";
if ( $customerEmailCount > $warningLimit )
{
    print MAIL "There may be a problem with emails from EPLAPP.\n$customerEmailCount emails have bounced\nCheck $bouncedCustomers for more details.\n";
}
elsif ( $customerEmailCount == 0 )
{
	print MAIL "There are no bounced messages.\n";
}

# mail stats to andrew.
my ($k, $v, $total);
format MAIL =
@####  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
$v, $k
.
format TOTAL =
-----
@####  total
$total
.
# mail stats to andrew.
print MAIL "\nBasic metrics:\n";
while( ($k, $v) = each %reasonCount ) 
{
	write MAIL;
}
print MAIL "\nDomains mailed:\n";
while( ($k, $v) = ( each %domainCount ) )
{
	write MAIL;
	$total += $v;
}
select(MAIL);
$~ = "TOTAL";
write MAIL;
close( MAIL );
# my @mailContent;
open( MAIL, "<$mailFile" ) or die "Unable to send mail report because: $!\n";
# @mailContent = <MAIL>;
my $mail = join( "", <MAIL> );
close( MAIL );
# my $mail = join( "", @mailContent );
sendMail( "Bounced email report", $stakeholders, $mail);
1;