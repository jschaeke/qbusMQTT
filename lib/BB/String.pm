#!/usr/bin/perl
##############################################################################
# Some handy string functions                                                #
#                                                                            #
# Author : Bart Boelaert                                                     #
# CopyRight (C) 2012 by Jolibo vof                                           #
# All Rights Reserved                                                        #
##############################################################################
# CHANGELOG                                                                  #
# ---------                                                                  #
# 2012/01/01 : Version 1.0                                                   #
#	* Initial release                                                    #
##############################################################################
package BB::String;
use strict;
use warnings;
use Carp;

use Exporter qw(import);
 
our $VERSION   = '1.0';
our @EXPORT = qw(Trim LTrim RTrim);
our @EXPORT_OK = qw(Trim LTrim RTrim);

# Perl trim function to remove whitespace from the start and end of the string
sub Trim
{
	# Check the number of arguments
	croak("Usage: Trim(\$String)") if @_ != 1;
	# Get the arguments
	my $string = shift;

	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

# Left trim function to remove leading whitespace
sub LTrim
{
	# Check the number of arguments
	croak("Usage: LTrim(\$String)") if @_ != 1;
	# Get the arguments
	my $string = shift;

	$string =~ s/^\s+//;
	return $string;
}

# Right trim function to remove trailing whitespace
sub RTrim
{
	# Check the number of arguments
	croak("Usage: RTrim(\$String)") if @_ != 1;
	# Get the arguments
	my $string = shift;

	$string =~ s/\s+$//;
	return $string;
}

1;
