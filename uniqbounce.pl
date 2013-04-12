#!/usr/bin/perl -w
###############################################################################
# Purpose: Finds and reports emails that have never been reported as bounced.
# Method:  Read the list of previously emailed customers into a list. Read
#          the list of new emails into another list. For each email on the
#          new list check the previous list and if already emailed discard
#          else save to file and push onto the previously emailed list. 
#          On completion write the updated previously emailed list to file.
#
#          This script does not alter the NDR.log file.
#          This script DOES overwrite the mailed.txt file of already emailed
#          customers.
#          This script creates a new email to_email list of customers every
#          time it is run but running the script multiple times will create
#          an empty file, and update, but not change mailed.txt.
#          The script will stop if it can't find either the mailed.txt or
#          NDR.log file or if it can't create a new to_email list.
#
# Usage:   perl uniqbounce.pl
#
# Author:  Andrew Nisbet, Edmonton Public Library.
# Date:    August 10, 2012
# Rev:     0.1 - April 12, 2012  Create the 'mailed.txt' file if it doesn't exist.
# Rev:     0.0 - August 10, 2012 Develop protected in repository on ilsdev1.epl.ca
##################################################################################

use strict;
use vars qw/ %opt /;
use Getopt::Std;

my $alreadyEmailedCustomerFile = "./mailed.txt";
my $bouncedEmailLog            = "./NDR.log";
my $fileTimeStamp              = localtime;  # e.g., "Thu Oct 13 04:54:34 1994"
$fileTimeStamp                 =~ s/\s/_/g;
my $customersToEmail           = "./to_mail_".$fileTimeStamp.".txt";
my $VERSION                    = "0.1";
my $DOMAIN                     = "example.com";

#
# Message about this program and how to use it
#
sub usage()
{
    print STDERR << "EOF";

	usage: $0 [-x] -d"hotmail.com"

Creates and maintains, a list of customer email address that have 
been notified that they have been mailed, but their domain ISP is 
blocking the receipt of that mail.

The script is looking for a '$alreadyEmailedCustomerFile' in the 
current directory, the NDR.log. It will create a '$customersToEmail'
in the current directory. If it doesn't find one it creates an empty
one then fills it. Once created and populated, keep the file around
until the blackout is over. It is the only reference you have to who
has been mailed. The '$customersToEmail' files can always be recreated.

Just run the script and notify the patrons in the dated patron list
file to check their accounts.

 -d : Domain that is blocking.
 -x : This (help) message.

example: $0

Version: $VERSION

EOF
    exit;
}

# Kicks off the setting of various switches.
# param:  
# return: 
sub init
{
    my $opt_string = 'xd:';
    getopts( "$opt_string", \%opt ) or usage();
    usage() if ($opt{'x'});
	if ($opt{'d'})
	{
		$DOMAIN = $opt{'d'};
	}
	else
	{
		usage();
	}
	# if a 'mailed.txt' file doesn't exist make one.
	if (not -e $alreadyEmailedCustomerFile)
	{
		`touch $alreadyEmailedCustomerFile`;
	}
}

init();

# open and read the list of customers we have already emailed, and create one if 
open(EMAILED_CUSTOMERS, "<$alreadyEmailedCustomerFile") or die "Error reading $alreadyEmailedCustomerFile: $!\n";
my %emailedCustomersList = map{$_ => 1} <EMAILED_CUSTOMERS>;
close(EMAILED_CUSTOMERS);

# open and read the list of customers that have bounced.
open(BOUNCED_CUSTOMERS, "<$bouncedEmailLog") or die "Error reading $bouncedEmailLog: $!\n";
my @bouncedCustomerList = <BOUNCED_CUSTOMERS>;
close(BOUNCED_CUSTOMERS);

print "number of customers already emailed: " . scalar(keys(%emailedCustomersList)) . "\n";
print "number of customers bounced        : " . scalar(@bouncedCustomerList) . "\n";


open(TOBEMAILED, ">$customersToEmail") or die "Error opening $customersToEmail: $!\n";
my $count = 0;
foreach my $bouncedCustomer (@bouncedCustomerList)
{
	# don't process date fields or blank lines.
	if ($bouncedCustomer =~ m/^\d/ or $bouncedCustomer =~ m/^\s/)
	{
		next;
	}
	# get the email address by itself.
	my @reasonAddress = split('\|', $bouncedCustomer);
	# print "$reasonAddress[1]";
	my $customerAddress = $reasonAddress[1];
	# filter for DOMAIN customers only.
	if ($customerAddress =~ m/($DOMAIN)/i)
	{
		# search the list of already emailed customers for this address.
		if (not ($emailedCustomersList{$customerAddress}))
		{
			print TOBEMAILED "$customerAddress";
			$emailedCustomersList{$customerAddress} = 1;
			$count++;
		}
	}
}
close(TOBEMAILED);
print "$count customers added to be emailed.\n";
open(NEW_EMAILED_CUSTOMERS, ">$alreadyEmailedCustomerFile") or die "Error reading $alreadyEmailedCustomerFile: $!\n";
for my $key ( sort( keys %emailedCustomersList )) 
{
	print NEW_EMAILED_CUSTOMERS "$key";
}
close(NEW_EMAILED_CUSTOMERS);
print "number of customers already emailed now: " . scalar(keys(%emailedCustomersList)) . "\n";
