#!/usr/bin/perl -w
#########################################################################################################################
# Purpose: Parses the /var/mail/sirsi file making note of accounts that 
#          have bounced and reporting strange trends like getting too
#          many bouncebacks which might indicate we have been blacklisted.
# Method:  Open /var/mail/sirsi, look for error notice in header, write 
#          explanation and address to file. Keep track of stats and
#          report them, including total bounced by reason.
# Parses bounced mail on Unix systems, reporting email address and reason.
#    Copyright (C) 2012, 2013  Andrew Nisbet Edmonton Public Library
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
# Author:  Andrew Nisbet, Edmonton Public Library.
# Dependencies: Uses xmail, but can be modified to use any Unix mailer, or none at all.
# Date:    July 13, 2012
# Rev:     0.8 - 2017-03-08 Fix warn messages while processing empty strings.
# Rev:     0.7 - 2014-05-20 Clean up for broader distribution.
# Rev:     0.6 - 2012-09-07 08:28:00 Saves unknown error codes to the non-fatal log.
# Rev:     0.5 - 2012-08-29 09:28:48 Added non-serious logging for diagnostics of patron mail.
# Rev:     0.4 - 2012-08-28 15:27:00 Fixed spelling and wording in  messages.
# Rev:     0.3 - 2012-08-23 12:53:31 Fixed bug that failed to load flat user if they had ACTIVE or INACTIVE ids on record.
# Rev:     0.2 - 2012-08-22 15:37:46 Initial release.
# Rev:     0.1 - 2012-08-13 14:44:26 Make file modified to include uniqbounce.pl since all can be done on server.
# Rev:     0.0 - 2012-07-09 14:11:07 Initialization of the project.
##########################################################################################################################
use strict;
use vars qw/ %opt /;
use Getopt::Std;
my $VERSION          = 0.8;
my $mailFile         = "mail.txt"; # Name of the report file that will be sent to the ILS admin.
my $noteHeader       = ""; # append "[address]. [Reason for bounceback.][date]".
my $mailbox          = "/var/mail/sirsi"; # name of the bounced mail file for the sirsi user.
my $bouncedCustomers = "NDR.log"; # File that contains the bounced emails and reasons: <comment string>|<email address>
my $warningLimit     = 100; # limit beyond which a warning is issued that we are getting too many bounced emails.
my $stakeholders     = qq{ilsadmins\@example.ca}; # list of parties interested in the amount of bounced email.
my $dierWarningSent  = 0; # if 0 no message sent yet, if true then suppress additional warnings about blacklisting.
my $failedAddresses  = "non_fatal_fail.log"; # Log of delivery failures that are not serious, but may be diagnostically helpful
my @exceptionAddresses = qw( ils_notice@example.com ilsadmins@example.com ); # list of addresses not to worry about during mail handling.
#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x][-c]

Handles the arduous task of updating users accounts if their emails don't work.
This script parses the bounced mail for the sirsi account on a Unix system. Please
note that you may need to change the location of the bounced mail file in this
script and the destination addresses of the ILS administrator.

The script reads and parses out the bounced accounts and reasons and creates a 
report in the current working directory. Once done, and if the -c flag is used
it will delete the mail file. The output file is then can be used for reporting
or as input for bounceback.pl, which will modify patron records to include information
about why they no longer receive mail from the library, and the date that occured.

 -c : Clean '$mailbox' file.
 -x : This (help) message.

example: $0 -c

Version: $VERSION

EOF
    exit;
}

# Returns a time stamp for the log file only. The Database uses the default
# time of writing the record for its time stamp in SQL. That was done to avoid
# the snarl of differences between MySQL and Perl time stamp details.
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
# Trim function to remove white space from the start and end of the string.
# param:  string to trim.
# return: string without leading or trailing spaces.
sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+// if ( $string );
	$string =~ s/\s+$// if ( $string );
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
		print getDate()." **Error: no mail to process in '$mailbox'. Are you sure thats where its located?\n";
		usage();
	}
	if ( -s $bouncedCustomers )
	{
		print "'$bouncedCustomers' exists.\nYesterdays list may not have been processed. Do you want to over write it? y[n] ";
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

#
# Returns true if the address is on the exceptions list and false otherwise
# param:  email address string - like ils_notice@example.ca
# return: 1 if on list and 0 otherwise.
sub isOnExceptionList
{
	my ( $address ) = $_[0];
	foreach my $exceptionalAddress ( @exceptionAddresses )
	{
		return 1 if ( lc( $exceptionalAddress ) eq lc( $address ) );
	}
	return 0;
}

init();
open SIRSI_MAIL, "<$mailbox" or die "Error opening $mailbox: $!\n";
open BOUNCED_CUSTOMERS, ">$bouncedCustomers" or die "Error opening $bouncedCustomers: $!\n";
print BOUNCED_CUSTOMERS "\n".getDate()."\n";
open POTENTIAL_PROBLEMS, ">>$failedAddresses" or die "Error opening $failedAddresses: $!\n";
print POTENTIAL_PROBLEMS "\n".getDate()."\n";
my $emailAddress    = "";
my %rejectionNotice = ();
$rejectionNotice{ 571 } = qq{our domain has been blacklisted by recipients domain};
$rejectionNotice{ 450 } = qq{Patrons mailbox is unreachable and may be corrupted, offline indefinitely, or our domain blacklisted by domain};
$rejectionNotice{ 554 } = qq{Recipients server believes our domains email is spam};
$rejectionNotice{ 553 } = qq{Mailbox address is invalid};
$rejectionNotice{ 551 } = qq{Relay denied, recipients ISP needs to allow our domain};
$rejectionNotice{ 550 } = qq{Patrons Mailbox is either disabled, suspended, firewall-blocking our domain, or does not exist};
$rejectionNotice{ 541 } = qq{Patrons firewall has rejected our domains mail};
$rejectionNotice{ 521 } = qq{Patrons email account is disabled};
$rejectionNotice{ 513 } = qq{Recipients mail server thinks the address is incorrectly formatted. Check for invalid characters};
$rejectionNotice{ 512 } = qq{The host server for the recipients domain name cannot be found};
$rejectionNotice{ 516 } = qq{Bad email address.};
$rejectionNotice{ 510 } = qq{Bad email address. Confirm spelling};
$rejectionNotice{ 511 } = qq{Bad email address. Confirm spelling};
$rejectionNotice{ 111 } = qq{Patrons mail server refused our connection request};
my %rejectionNoticeNotSerious = ();
$rejectionNoticeNotSerious{ 443 } = qq{Patrons mail server dropped connection or is not responding};
$rejectionNoticeNotSerious{ 447 } = qq{Patrons mail server timed out during delivery};
$rejectionNoticeNotSerious{ 500 } = qq{Patron servers firewall or anti-virus software may be interfering with mail delivery};
$rejectionNoticeNotSerious{ 422 } = qq{Patrons mail box is full};
$rejectionNoticeNotSerious{ 552 } = qq{Mail aborted because mailbox is full};
my %reasonCount;
my %domainCount;
my $customerEmailCount = 0;
my %uniquePatronEmails;
my $ignoreAccount     = 0;
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
		# reset this (if set). It sanitizes malformed email local names in addresses.
		$ignoreAccount = 0;
		# snag the address while we can, if Action turns out to be failed then we will use it.
		my @finalRecipientAddress = split( ';', $_ );
		$emailAddress = trim( $finalRecipientAddress[1] );
		if ( $emailAddress )
		{
			# some emails come back with angle brackets.
			$emailAddress =~ s/[<>]//g;
			my @nameDomain = split( '\@', $emailAddress );
			if ( $nameDomain[0] =~ m/^[\*\.\?\+]/ )
			{
				printf STDERR "\n***\n*** Warning: malformed email local name detected: '%s'\n***\n", $nameDomain[0];
				# Stop this from processing.
				$ignoreAccount = 1;
			}
			my $domain = lc( $nameDomain[1] );
			# Keep a count of all the domains we handled today.
			$domainCount{ $domain }++;
		}
		else
		{
			printf STDERR "\n*** Warning: malformed email: '%s'\n***\n", $finalRecipientAddress[1];
		}
	}
	if ( $_ =~ m/^Status:/i )
	{
		next if ( $ignoreAccount );
		my @statusReason = split( ':', $_ );
		$statusReason[1] =~ s/\.//g;
		$statusReason[1] =~ s/^\s+//g;
		my $status = substr($statusReason[1], 0, 3);
		print "---->$status<-----\n" if ( $opt{'d'} );
		if ( $rejectionNotice{ $status } )
		{
			# here we send an early warning message if the status is about being blacklisted.
			if ( $status == 571 )
			{
				# TODO add exceptions list here. ils_notice@example.ca should not trigger an email or account email deletion ever.
				if ( isOnExceptionList( $emailAddress ) )
				{
					next;
				}
				if ( not $dierWarningSent )
				{
					my $msg = "A patrons email ($emailAddress) was returned because we was blacklisted, please investigate.";
					sendMail( "***Blacklist Warning***", "ilsadmin\@example.ca", $msg );
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
		# not serious list; these get noted, but patron's accounts are not updated.
		elsif ( $rejectionNoticeNotSerious{ $status } )
		{
			$noteHeader = $rejectionNoticeNotSerious{ $status };
			$reasonCount{ $rejectionNoticeNotSerious{ $status } }++;
			print POTENTIAL_PROBLEMS "$noteHeader|$emailAddress\n";
		}
		else # unknown probably harmless status was found. Don't edit patron account, but do record it to non-fatal.
		{
			$reasonCount{ $status }++;
			print POTENTIAL_PROBLEMS "unknown error: '$status'|$emailAddress\n";
		}
	}
}
$customerEmailCount = scalar( keys( %uniquePatronEmails ) );
close BOUNCED_CUSTOMERS;
close POTENTIAL_PROBLEMS;
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

# mail stats to ILS administrator.
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
# mail stats to ils administrator.
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
sendMail( "Bounced email report", $stakeholders, $mail );
# EOF