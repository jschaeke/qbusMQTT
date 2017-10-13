#! /usr/bin/perl
##############################################################################
# Some handy number functions                                                #
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
package BB::Number;
use strict;
use warnings;
use Carp;

use Exporter qw(import);
 
our $VERSION   = '1.0';
our @EXPORT = qw(Round IsNumeric);
our @EXPORT_OK = qw(Round IsNumeric);

 
sub Round
{
	# Check the number of arguments
	croak("Usage: Round(\$Number, \$Decimals)") if @_ != 2;
	# Get the arguments
	my ($number, $decimals)  = @_;
	my $factor = 10 ** ($decimals || 0);

	if (!IsNumeric($number))
	{
		return -1;
	};
	return int(($number * $factor) + ($number < 0 ? -1 : 1) * 0.5) / $factor;
}


sub IsNumeric
{
	# Check the number of arguments
	croak("Usage: IsNumeric(\$Number)") if @_ != 1;
	# Get the arguments
	my $x = shift;

	if ($x !~ /^[0-9|.|,]*$/)
	{
		return 0;
	}
	else
	{
		return 1;
	};
}


1;