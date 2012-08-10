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
# Usage:   Cygwin: perl uniqbounce.pl
#
# Author:  Andrew Nisbet, Edmonton Public Library.
# Date:    August 10, 2012
# Rev:     0.0 - August 10, 2012 Develop protected in repository on ilsdev1.epl.ca
##################################################################################

use strict;

my $alreadyEmailedCustomerFile = "./mailed.txt";
my $bouncedEmailLog            = "./NDR.log";
my $fileTimeStamp              = localtime;  # e.g., "Thu Oct 13 04:54:34 1994"
$fileTimeStamp                 =~ s/\s/_/g;
my $customersToEmail           = "./to_mail_".$fileTimeStamp.".txt";

# open and read the list of customers we have already emailed
open(EMAILED_CUSTOMERS, "<$alreadyEmailedCustomerFile") or die "Error reading $alreadyEmailedCustomerFile: $!\n";
my %emailedCustomersList = map{$_ => 1} <EMAILED_CUSTOMERS>;
close(EMAILED_CUSTOMERS);

# open and read the list of customers that have bounced.
open(BOUNCED_CUSTOMERS, "<$bouncedEmailLog") or die "Error reading $bouncedEmailLog: $!\n";
my @bouncedCustomerList = <BOUNCED_CUSTOMERS>;
close(BOUNCED_CUSTOMERS);

print "number of customers already emailed: " . scalar(keys(%emailedCustomersList)) . "\n";
print "number of customers bounced        : " . scalar(@bouncedCustomerList) . "\n";


open(TBEMAILED, ">$customersToEmail") or die "Error opening $customersToEmail: $!\n";
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
	# filter for MSN customers only.
	if ($customerAddress =~ m/hotmail/i or $customerAddress =~ m/live/i)
	{
		# search the list of already emailed customers for this address.
		if (not $emailedCustomersList{$customerAddress})
		{
			print TBEMAILED "$customerAddress";
			$emailedCustomersList{$customerAddress} = 1;
			$count++;
		}
	}
}
close(TBEMAILED);
print "$count customers added to be emailed.\n";
open(NEW_EMAILED_CUSTOMERS, ">$alreadyEmailedCustomerFile") or die "Error reading $alreadyEmailedCustomerFile: $!\n";
for my $key ( sort( keys %emailedCustomersList )) 
{
	print NEW_EMAILED_CUSTOMERS "$key";
}
close(NEW_EMAILED_CUSTOMERS);
print "number of customers already emailed now: " . scalar(keys(%emailedCustomersList)) . "\n";
1;