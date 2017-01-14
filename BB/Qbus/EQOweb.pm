#! /usr/bin/perl -w
##############################################################################
# Library functions for interacting with the Qbus ECOweb interface of a Qbus #
# CTD controller                                                             #
#                                                                            #
# Author : Bart Boelaert                                                     #
# CopyRight (C) 2014 by Jolibo vof                                           #
# All Rights Reserved                                                        #
##############################################################################
# CHANGELOG                                                                  #
# ---------                                                                  #
# 2014/12/01 : Version 1.0                                                   #
#	* Initial release  														 #
# 2016/01/12 : Version 1.0.1												 #
#   * Adapted for use with MQTT  (Jeroen Schae                               #
##############################################################################
package EQOweb;

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;
use HTTP::Request::Common;
use JSON;
use Data::Dumper;
use Carp;
use Switch;
use BB::Number;

our $VERSION   = "1.0";

my %QBusCommands = ("ERROR", 0, "LOGIN", 1, "LOGIN_RESPONSE", 2, "GET_GROUPS", 10, "GET_GROUPS_RESPONSE", 11, "SET_STATUS", 12, "SET_STATUS_RESPONSE", 13, "GET_STATUS", 14, "GET_STATUS_RESPONSE", 15);
my %QBusChannelTypes = ("TOGGLE", 0, "DIMMER", 1, "SET_TEMP", 2, "PROG_TEMP", 3, "SHUTTERS", 4, "AUDIO", 5, "SCENES", 7);
my %QBusErrorCodes= ("PARSE_ERROR", 0, "ARGUMENT_ERROR", 1, "CONNECTION_ERROR", 2, "LOGIN_ERROR", 3, "UNDEFINED_ERROR", 4);

sub getChannelTypes {
	return %QBusChannelTypes;
}
sub new
{
	my $class = shift;
	my $self  = { @_ };

	if (!defined($self->{QbusCTLIP}))
	{
		croak("Usage: new ({QbusCTLIP => \"100.100.100.100", UserName => \"MyUserName\", Password => \"MyPassword\" [, ForceSessionID = \"0209B8F9\", Debug => [0|1] ]})");
	};

	# Initialize object variables with defaults if not specified
	$self->{UserName} = ""	unless defined($self->{UserName});
	$self->{Password} = ""	unless defined($self->{Password});
	$self->{Reconnect} = 0	unless defined($self->{Reconnect});
	$self->{MaxReconnectAttempts} = 0 unless defined($self->{MaxReconnectAttempts});
	$self->{WaitSecsB4Reconnect} = 1 unless defined($self->{WaitSecsB4Reconnect});
	$self->{ReconnectAttempts} = 0;
	$self->{Debug} = 0	unless defined($self->{Debug});
	$self->{QBusCTLURL} = "http://" . $self->{QbusCTLIP} . ":8444/default.aspx?r=";
	$self->{objBrowser} = LWP::UserAgent->new;
	$self->{objBrowser}->agent("LibQBus/1.0");
	$self->{objCookieJar} = HTTP::Cookies->new();
	$self->{Channels} = undef;
	if (defined($self->{ForceSessionID}))
	{
		$self->{SessionID} = $self->{ForceSessionID};
		$self->{objCookieJar}->set_cookie( 1, "i", $self->{SessionID}, "/", $self->{QbusCTLIP}, 8444, 0 , 0, 24*3600, 0);
		$self->{Connected} = 1;
	}
	else
	{
		$self->{Connected} = 0;
	};
	$self->{LastError} = "";

	return bless $self, $class; #this is what makes a reference into an object
}

sub Version
{
	return $VERSION;
}

sub Connect
{
	my $self = shift;
	my $strFunction = "Connect()";
	my $objJSON = new JSON();
	my $objRequest;
	my $objResponse;
	my $strURL;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Only do the connect procedure when we're not logged in (anymore, because of a session time-out)
	unless($self->{Connected})
	{
		# Initializing objects and variables
		$strURL = $self->{QBusCTLURL} . rand(); 

		($self->{Debug}) && print("Posting LOGIN request to $strURL ...\n");
		$self->{objBrowser}->cookie_jar($self->{objCookieJar});
		$objRequest = HTTP::Request::Common::POST(
								$strURL,
								[
									"strJSON"  => "{\"Type\":" . $QBusCommands{"LOGIN"} . ",\"Value\":{\"Usr\":\"" . $self->{UserName} . "\",\"Psw\":\"" . $self->{Password} . "\"}}"
								],
								);
		$self->{objBrowser}->prepare_request($objRequest);
		($self->{Debug}) && print("Raw Request :\n");
		($self->{Debug}) && print($objRequest->as_string);
		$objResponse = $self->{objBrowser}->send_request($objRequest);
		if (!($objResponse->is_success))
		{
			$self->{LastError} = "Could not post LOGIN request to $strURL : " . $objResponse->status_line();
			return 0;
		};
		($self->{Debug}) && print("QBus controller response :\n" . $objResponse->content . "\n");
		# Check the response
		($self->{Debug}) && print("Checking QBus controller response ...\n");
		my $hash_ref = $objJSON->decode($objResponse->content);
		if ($hash_ref->{"Type"} == $QBusCommands{"ERROR"})
		{
			$self->{LastError} = "The following error was received from QBus controller : " . GetCTLErrorDescription($hash_ref->{"Value"}->{"Error"});
			if ($hash_ref->{"Value"}->{"Error"} != 6)
			{
				$self->{Connected} = 0;
				return $self->Reconnect();
			};
			return 0;
		};
		if ($hash_ref->{"Type"} != $QBusCommands{"LOGIN_RESPONSE"})
		{
			$self->{LastError} = "Invalid response type (" . $hash_ref->{"Type"} . ") received from QBus controller!";
			return 0;
		};
#		if ($hash_ref->{"Value"}->{"rsp"} ne "true")
#		{
#			$self->{LastError} = "Invalid Username/Password!";
#			return 0;
#		};

		# Here we are sure the login was successful
		$self->{Connected} = 1;
		($self->{Debug}) && print("Login successful! (Session ID = " . $hash_ref->{"Value"}->{"id"} . ")\n");

		($self->{Debug}) && print("Storing credentials in Cookie variables ...\n");
		# Since v3.3.0, only id is needed in the cookie
		if (defined($hash_ref->{"Value"}->{"id"}))
		{
			$self->{SessionID} = $hash_ref->{"Value"}->{"id"};
			$self->{objCookieJar}->set_cookie( 1, "i", $hash_ref->{"Value"}->{"id"}, "/", $self->{QbusCTLIP}, 8444, 0 , 0, 24*3600, 0);
		}
		else
		{
			$self->{objCookieJar}->set_cookie( 1, "l", $self->{UserName}, "/", $self->{QbusCTLIP}, 8444, 0 , 0, 24*3600, 0);
			$self->{objCookieJar}->set_cookie( 1, "p", $self->{Password}, "/", $self->{QbusCTLIP}, 8444, 0 , 0, 24*3600, 0);
		};
	};
	if (!$self->{Channels})
	{
		($self->{Debug}) && print("Retrieving all channels from QBus controller ...\n");
		$self->{Channels} = $self->GetGroups();
		if (!$self->{Channels})
		{
			return 0;
		};
	};	
		
	# Return success
	return 1;
};


sub Reconnect()
{
	my $self = shift;
	my $ret = 0;

	while ($self->{ReconnectAttempts} < $self->{MaxReconnectAttempts})
	{
		($self->{ReconnectAttempts})++;
		sleep($self->{WaitSecsB4Reconnect});
		($self->{Debug}) && print("Reconnecting to QBus controller (Attempt #" . $self->{ReconnectAttempts} . ")\n");
		$ret = $self->Connect();
		if ($ret)
		{
			last;
		};
	};
	return $ret;

};

sub GetStatusByChannelID
{
	my $self = shift;
	my $objJSON = new JSON();
	my $objRequest;
	my $objResponse;
	my $strURL;

	# Initialize objects and variables
	$self->{LastError} = "";
	
	# Check the number of arguments
	croak("Usage: GetStatusByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetStatusByChannelID(\$ChannelID)");
	};

	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};

	$strURL = $self->{QBusCTLURL} . rand(); 
	($self->{Debug}) && print("Posting GET_STATUS request to $strURL ...\n");
	$self->{objBrowser}->cookie_jar($self->{objCookieJar});
	$objRequest = HTTP::Request::Common::POST(
						$strURL,
						[
							"strJSON"  => "{\"Type\":" . $QBusCommands{"GET_STATUS"} . ",\"Value\":{\"Chnl\":$ChannelID}}"
						],
						);
	$self->{objBrowser}->prepare_request($objRequest);
	($self->{Debug}) && print("Raw Request :\n");
	($self->{Debug}) && print($objRequest->as_string);
	$objResponse = $self->{objBrowser}->send_request($objRequest);
	if (!($objResponse->is_success))
	{
		$self->{LastError} = "Could not post GET_STATUS request to $strURL : " . $objResponse->status_line();
		return -1;
	};
	($self->{Debug}) && print("QBus controller response :\n" . $objResponse->content . "\n");
	# Check the response
	($self->{Debug}) && print("Checking QBus controller response ...\n");
	my $hash_ref = $objJSON->allow_nonref->decode($objResponse->content);
	if ($hash_ref->{"Type"} == $QBusCommands{"ERROR"})
	{
		$self->{LastError} = "The following error was received from QBus controller : " . GetCTLErrorDescription($hash_ref->{"Value"}->{"Error"});
		if ($hash_ref->{"Value"}->{"Error"} != 6)
		{
			$self->{Connected} = 0;
			if ($self->Reconnect())
			{
				return $self->GetStatusByChannelID($ChannelID);
			};
		};
		return -1;
	};
	if ($hash_ref->{"Type"} != $QBusCommands{"GET_STATUS_RESPONSE"})
	{
		$self->{LastError} = "Invalid response type (" . $hash_ref->{"Type"} . ") received from QBus controller!";
		return -1;
	};
	if ($hash_ref->{"Value"}->{"Chnl"} != $ChannelID)
	{
		$self->{LastError} = "Invalid ChannelID (" . $hash_ref->{"Value"}->{"Chnl"} . ") received from QBus controller!";
		return -1;
	};
	if ($#{$hash_ref->{"Value"}->{"Val"}} > 0)
	{
		($self->{Debug}) && print("Returning value " . ${$hash_ref->{"Value"}->{"Val"}}[0] . " and " . ${$hash_ref->{"Value"}->{"Val"}}[1] . "\n");
		return(${$hash_ref->{"Value"}->{"Val"}}[0], ${$hash_ref->{"Value"}->{"Val"}}[1]);
	}
	else
	{
		($self->{Debug}) && print("Returning value " . ${$hash_ref->{"Value"}->{"Val"}}[0] . "\n");
		return(${$hash_ref->{"Value"}->{"Val"}}[0]);
	};
}


sub SetStatusByChannelID
{
	my $self = shift;
	my $objJSON = new JSON();
	my $objRequest;
	my $objResponse;
	my $strURL;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetStatusByChannelID(\$ChannelID, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $Status) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($Status)))
	{
		croak("Usage: SetStatusByChannelID(\$ChannelID, \$Status)");
	};

	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};

	$strURL = $self->{QBusCTLURL} . rand(); 
	($self->{Debug}) && print("Posting SET_STATUS request to $strURL ...\n");
	$self->{objBrowser}->cookie_jar($self->{objCookieJar});
	$objRequest = HTTP::Request::Common::POST(
						$strURL,
						[
							"strJSON"  => "{\"Type\":" . $QBusCommands{"SET_STATUS"} . ",\"Value\":{\"Chnl\":$ChannelID,\"Val\":[$Status]}}"
						],
						);
	$self->{objBrowser}->prepare_request($objRequest);
	($self->{Debug}) && print("Raw Request :\n");
	($self->{Debug}) && print($objRequest->as_string);
	$objResponse = $self->{objBrowser}->send_request($objRequest);
	if (!($objResponse->is_success))
	{
		$self->{LastError} = "Could not post SET_STATUS request to $strURL : " . $objResponse->status_line();
		return 0;
	};
	($self->{Debug}) && print("QBus controller response :\n" . $objResponse->content . "\n");
	# Check the response
	($self->{Debug}) && print("Checking QBus controller response ...\n");
	# Check the response
	my $hash_ref = $objJSON->allow_nonref->decode($objResponse->content);
	if ($hash_ref->{"Type"} == $QBusCommands{"ERROR"})
	{
		$self->{LastError} = "The following error was received from QBus controller : " . GetCTLErrorDescription($hash_ref->{"Value"}->{"Error"});
		if ($hash_ref->{"Value"}->{"Error"} != 6)
		{
			$self->{Connected} = 0;
			if ($self->Reconnect())
			{
				return $self->SetStatusByChannelID($ChannelID, $Status);
			};
		};
		return 0;
	};
	if ($hash_ref->{"Type"} != $QBusCommands{"SET_STATUS_RESPONSE"})
	{
		$self->{LastError} = "Invalid response type (" . $hash_ref->{"Type"} . ") received from QBus controller!";
		return 0;
	};
	if ($hash_ref->{"Value"}->{"Chnl"} != $ChannelID)
	{
		$self->{LastError} = "Invalid ChannelID (" . $hash_ref->{"Value"}->{"Chnl"} . ") received from QBus controller!";
		return 0;
	};
	if (${$hash_ref->{"Value"}->{"Val"}}[0] != $Status)
	{
		$self->{LastError} = "Invalid status (" . $hash_ref->{"Value"}->{"Val"} . ") received from QBus controller!";
		return 0;
	};
	# Return success
	return 1;
}


sub GetChannelInfoByID
{
	my $self = shift;
	# Initialize objects and variables
	$self->{LastError} = "";
	
	# Check the number of arguments
	croak("Usage: GetChannelInfoByID(\$ChannelID, \$sr_ChannelName, \$sr_ChannelType, \$sr_ChannelValue)") if @_ != 4;
	# Get the arguments
	my ($ChannelID, $sr_ChannelName, $sr_ChannelType, $sr_ChannelValue) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($sr_ChannelName)) || (!defined($sr_ChannelType)) || (!defined($sr_ChannelValue)))
	{
		croak("Usage: GetChannelInfoByID(\$ChannelID, \$sr_ChannelName, \$sr_ChannelType, \$sr_ChannelValue)");
	};

	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};

	($self->{Debug}) && print("Iterating QBus Channels ...\n");
	for my $Group (@{$self->{Channels}->{"Groups"}})
	{
		($self->{Debug}) && print("Iterating Channel Group \"" . $Group->{"Nme"} . "\" ...\n");
		for my $GroupItem (@{$Group->{"Itms"}})
		{
			($self->{Debug}) && print("Checking ChannelID \"" . $GroupItem->{"Chnl"} . "\" ...\n");
			if ($GroupItem->{"Chnl"} eq $ChannelID)
			{
				$$sr_ChannelName = $GroupItem->{"Nme"};
				$$sr_ChannelType = $GroupItem->{"Ico"};
				$$sr_ChannelValue = $GroupItem->{"Val"};
				return 1;
			};
		};
	};
	$self->{LastError} = "ChannelID $ChannelID not found!";
	return 0;
};


sub mapChannelInfo
{
	my $self = shift;
	# Initialize objects and variables
	$self->{LastError} = "";
	
	# Check the number of arguments
	croak("Usage: mapChannelInfo(\$mapper)") if @_ != 1;
	# Get the arguments
	my ($mapper) = @_;
	
	($self->{Debug}) && print("Mapper: Iterating QBus Channels ...\n");
	for my $Group (@{$self->{Channels}->{"Groups"}})
	{
		($self->{Debug}) && print("Iterating Channel Group \"" . $Group->{"Nme"} . "\" ...\n");
		for my $GroupItem (@{$Group->{"Itms"}})
		{
			($self->{Debug}) && print("Checking ChannelID \"" . $GroupItem->{"Chnl"} . "\" ...\n");
			#if ($GroupItem->{"Chnl"} eq $ChannelID)
			#{
				my $channelId = $GroupItem->{"Chnl"};
				my $status = $self->GetStatusByChannelID($channelId);
				my $devType = $GroupItem->{"Ico"};
				$mapper->($channelId,$status,$devType);
				#print($GroupItem->{"Ico"} . " " . $GroupItem->{"Nme"} . " " . $channelId . " = " . $status . "\n");
				#$$sr_ChannelName = $GroupItem->{"Nme"};
				#$$sr_ChannelType = $GroupItem->{"Ico"};
				#$$sr_ChannelValue = $GroupItem->{"Val"};
				#return 1;
			#};
		};
	};
	$self->{LastError} = "Mapper failed ohoh!";
	return 0;
};


sub GetChannelInfoByName
{
	my $self = shift;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetChannelInfoByName(\$ChannelName, \$ChannelType, \$sr_ChannelID, \$sr_ChannelValue)") if @_ != 4;
	# Get the arguments
	my ($ChannelName, $ChannelType, $sr_ChannelID, $sr_ChannelValue) = @_;
	# Check the arguments
	if ((!defined($ChannelName)) || (!defined($ChannelType)) || (!defined($sr_ChannelID)) || (!defined($sr_ChannelValue)))
	{
		croak("Usage: GetChannelInfoByName(\$ChannelName, \$ChannelType, \$sr_ChannelID, \$sr_ChannelValue)");
	};

	if ($ChannelName eq "")
	{
		$self->{LastError} = "ChannelName is empty!";
		return 0;
	};
	if (!IsNumeric($ChannelType))
	{
		$self->{LastError} = "ChannelType is not numeric!";
		return 0;
	};
	if (
		($ChannelType != $QBusChannelTypes{"TOGGLE"}) &&
		($ChannelType != $QBusChannelTypes{"DIMMER"}) &&
		($ChannelType != $QBusChannelTypes{"SET_TEMP"}) &&
		($ChannelType != $QBusChannelTypes{"PROG_TEMP"}) &&
		($ChannelType != $QBusChannelTypes{"SHUTTERS"}) &&
		($ChannelType != $QBusChannelTypes{"AUDIO"}) &&
		($ChannelType != $QBusChannelTypes{"SCENES"})
	   )
	{
		$self->{LastError} = "Invalid ChannelType specified!";
		return 0;
	};

	($self->{Debug}) && print("Iterating QBus Channels ...\n");
	for my $Group (@{$self->{Channels}->{"Groups"}})
	{
		($self->{Debug}) && print("Iterating Channel Group \"" . $Group->{"Nme"} . "\" ...\n");
		for my $GroupItem (@{$Group->{"Itms"}})
		{
			($self->{Debug}) && print("Checking Channel Name \"" . $GroupItem->{"Nme"} . "\" ...\n");
			if ((lc($GroupItem->{"Nme"}) eq lc($ChannelName)) && ($GroupItem->{"Ico"} == $ChannelType))
			{
				$$sr_ChannelID = $GroupItem->{"Chnl"};
				$$sr_ChannelValue = $GroupItem->{"Val"};
				return 1;
			};
		};
	};
	$self->{LastError} = "Channel Name \"$ChannelName\" not found!";
	return 0;
};


sub GetGroups
{
	my $self = shift;
	my $objJSON = new JSON();
	my $objRequest;
	my $objResponse;
	my $strURL;

	# Initialize objects and variables
	$self->{LastError} = "";
	$strURL = $self->{QBusCTLURL} . rand(); 

	($self->{Debug}) && print("Posting GET_GROUPS request to $strURL ...\n");
	$self->{objBrowser}->cookie_jar($self->{objCookieJar});
	$objRequest = HTTP::Request::Common::POST(
						$strURL,
						[
							"strJSON"  => "{\"Type\":" . $QBusCommands{"GET_GROUPS"} . ",\"Value\":null}"
						],
						);
	$self->{objBrowser}->prepare_request($objRequest);
	($self->{Debug}) && print("Raw Request :\n");
	($self->{Debug}) && print($objRequest->as_string);
	$objResponse = $self->{objBrowser}->send_request($objRequest);
	if (!($objResponse->is_success))
	{
		$self->{LastError} = "Could not post GET_GROUPS request to $strURL : " . $objResponse->status_line();
		return 0;
	};
	($self->{Debug}) && print("QBus controller response :\n" . $objResponse->content . "\n");
	# Check the response
	($self->{Debug}) && print("Checking QBus controller response ...\n");
	my $hash_ref = $objJSON->decode($objResponse->content);
	if ($hash_ref->{"Type"} == $QBusCommands{"ERROR"})
	{
		$self->{LastError} = "The following error was received from QBus controller : " . GetCTLErrorDescription($hash_ref->{"Value"}->{"Error"});
		if ($hash_ref->{"Value"}->{"Error"} != 6)
		{
			$self->{Connected} = 0;
			if ($self->Reconnect())
			{
				return $self->{Channels};
			};
		};
		return 0;
	};
	if ($hash_ref->{"Type"} != $QBusCommands{"GET_GROUPS_RESPONSE"})
	{
		$self->{LastError} = "Invalid response type (" . $hash_ref->{"Type"} . ") received from QBus controller!";
		return 0;
	};
	# print Data::Dumper->Dump([$hash_ref]);
	unless(defined($hash_ref->{"Value"}))
	{
		$self->{LastError} = "Empty groups received from QBus controller!";
		return 0;
	}
	return $hash_ref->{"Value"};
}


sub ThermostatProgName
{
	my $self = shift;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: ThermostatProgName(\$ThermostatProgID)") if @_ != 1;
	# Get the arguments
	my $ThermostatProgID = shift;
	# Check the arguments
	if (!defined($ThermostatProgID))
	{
		croak("Usage: ThermostatProgName(\$ThermostatProgID)");
	};
	if (!IsNumeric($ThermostatProgID))
	{
		$self->{LastError} = "ThermostatProgID is not numeric!";
		return undef;
	};
	switch($ThermostatProgID)
	{
		case 0	{return "Manual"; }
		case 1	{return "Away"; }
		case 2	{return "Economy"; }
		case 3	{return "Comfort"; }
		case 4	{return "Night"; }
		else
		{
			$self->{LastError} = "Invalid ThermostatProgID!";
			return undef;
		}
	};
}


sub ThermostatProgID
{
	my $self = shift;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: ThermostatProgID(\$ThermostatProgName)") if @_ != 1;
	# Get the arguments
	my $ThermostatProgName = shift;
	# Check the arguments
	if (!defined($ThermostatProgName))
	{
		croak("Usage: ThermostatProgID(\$ThermostatProgName)");
	};
	if ($ThermostatProgName eq "")
	{
		$self->{LastError} = "ThermostatProgName not specified!";
		return -1;
	};
	switch($ThermostatProgName)
	{
		case "Manual"	{return 0; }
		case "Away"	{return 1; }
		case "Economy"	{return 2; }
		case "Comfort"	{return 3; }
		case "Night"	{return 4; }
		else
		{
			$self->{LastError} = "Invalid ThermostatProgName!";
			return -1;
		}
	};

}


sub ShutterStatusName
{
	my $self = shift;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: ShutterStatusName(\$ShutterStatusID)") if @_ != 1;
	# Get the arguments
	my $ShutterStatusID = shift;
	# Check the arguments
	if (!defined($ShutterStatusID))
	{
		croak("Usage: ShutterStatusName(\$ShutterStatusID)");
	};
	if (!IsNumeric($ShutterStatusID))
	{
		$self->{LastError} = "ShutterStatusID is not numeric!";
		return undef;
	};
	switch($ShutterStatusID)
	{
		case 0		{return "Stop"; }
		case 1		{return "Up"; }
		case 2		{return "Down"; }
		case 255	{return "Running"; }
		else
		{
			$self->{LastError} = "Invalid ShutterStatusID!";
			return undef;
		}
	};

}


sub ShutterStatusID
{
	my $self = shift;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: ShutterStatusID(\$ShutterStatusName)") if @_ < 1 || @_ > 2;
	# Get the arguments
	my $ShutterStatusName = shift;
	# Check the arguments
	if (!defined($ShutterStatusName))
	{
		croak("Usage: ShutterStatusID(\$ShutterStatusName)");
	};
	if ($ShutterStatusName eq "")
	{
		$self->{LastError} = "ShutterStatusName not specified!";
		return -1;
	};
	switch($ShutterStatusName)
	{
		case "Stop"		{return 0; }
		case "Up"		{return 1; }
		case ["Down", "Dn"]	{return 2; }
		else
		{
			$self->{LastError} = "Invalid ShutterStatusName!";
			return -1;
		}
	};

}

sub ShutterPStatusName
{
	my $self = shift;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: ShutterPStatusName(\$ShutterPStatusValue)") if @_ != 1;
	# Get the arguments
	my $ShutterPStatusValue = shift;
	# Check the arguments
	if (!defined($ShutterPStatusValue))
	{
		croak("Usage: ShutterPStatusName(\$ShutterStatusValue)");
	};
	if (!IsNumeric($ShutterPStatusValue))
	{
		$self->{LastError} = "ShutterStatusID is not numeric!";
		return undef;
	};
	if (($ShutterPStatusValue < 0) || ($ShutterPStatusValue > 100))
	{
		$self->{LastError} = "Invalid ShutterPStatusValue!";
		return undef;
	};
	switch($ShutterPStatusValue)
	{
		case 0		{return "Down"; }
		case 100	{return "Up"; }
		else
		{
			return "$ShutterPStatusValue%";
		}
	};
}


sub GetToggleStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetToggleStatusByChannelID(\$ChannelID, function)") if @_ != 2;
	# Get the arguments
	#my $ChannelID = shift;
	my ($ChannelID, $func) = @_;
	$func->();
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetToggleStatusByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"TOGGLE"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a toggle!";
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	if($Status > 0)
	{
		$Status = 1;
	}
	else
	{
		$Status = 0;
	};
	return $Status;
}


sub SetToggleStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetToggleStatusByChannelID(\$ChannelID, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $Status) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($Status)))
	{
		croak("Usage: SetToggleStatusByChannelID(\$ChannelID, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Toggle status is not numeric!";
		return 0;
	};
	if (($Status != 0) && ($Status != 1))
	{
		$self->{LastError} = "Toggle status should be 0 (=OFF) or 1 (=ON)!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"TOGGLE"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a toggle!";
		return 0;
	};
	if($Status)
	{
		$Status = 255;
	};
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetToggleStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetToggleStatusByName(\$ToggleName)") if @_ != 1;
	# Get the arguments
	my $ToggleName = shift;
	# Check the arguments
	if (!defined($ToggleName))
	{
		croak("Usage: GetToggleStatusByName(\$ToggleName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($ToggleName eq "")
	{
		$self->{LastError} = "Toggle Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($ToggleName, $QBusChannelTypes{"TOGGLE"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	if($Status > 0)
	{
		$Status = 1;
	}
	else
	{
		$Status = 0;
	};
	return $Status;
}


sub SetToggleStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetToggleStatusByName(\$ToggleName, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ToggleName, $Status) = @_;
	# Check the arguments
	if ((!defined($ToggleName)) || (!defined($Status)))
	{
		croak("Usage: SetToggleStatusByName(\$ToggleName, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($ToggleName eq "")
	{
		$self->{LastError} = "Toggle Name not specified!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Toggle status is not numeric!";
		return 0;
	};
	if (($Status != 0) && ($Status != 1))
	{
		$self->{LastError} = "Toggle status should be 0 (=OFF) or 1 (=ON)!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($ToggleName, $QBusChannelTypes{"TOGGLE"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	if($Status)
	{
		$Status = 255;
	};
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetDimmerStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetDimmerStatusByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetDimmerStatusByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"DIMMER"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a dimmer!";
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	if ($Status > 0)
	{
		$Status = Round($Status / 255 * 100, 0);
	};
	return $Status;
}


sub SetDimmerStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetDimmerStatusByChannelID(\$ChannelID, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $Status) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($Status)))
	{
		croak("Usage: SetDimmerStatusByChannelID(\$ChannelID, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Dimmer status is not numeric!";
		return 0;
	};
	if (($Status < 0) || ($Status > 100))
	{
		$self->{LastError} = "Dimmer status should be between 0 (=0% or OFF) and 100 (=100% or ON)!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"DIMMER"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a dimmer!";
		return 0;
	};
	$Status = Round($Status / 100 * 255, 0);
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetDimmerStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetDimmerStatusByName(\$DimmerName)") if @_ != 1;
	# Get the arguments
	my $DimmerName = shift;
	# Check the arguments
	if (!defined($DimmerName))
	{
		croak("Usage: GetDimmerStatusByName(\$DimmerName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($DimmerName eq "")
	{
		$self->{LastError} = "Dimmer Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($DimmerName, $QBusChannelTypes{"DIMMER"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	if ($Status > 0)
	{
		$Status = Round($Status / 255 * 100, 0);
	};
	return $Status;
}


sub SetDimmerStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetDimmerStatusByName(\$DimmerName, \$Status)") if @_ != 2;
	# Get the arguments
	my ($DimmerName, $Status) = @_;
	# Check the arguments
	if ((!defined($DimmerName)) || (!defined($Status)))
	{
		croak("Usage: SetDimmerStatusByName(\$DimmerName, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($DimmerName eq "")
	{
		$self->{LastError} = "Dimmer Name not specified!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Dimmer status is not numeric!";
		return 0;
	};
	if (($Status < 0) || ($Status > 100))
	{
		$self->{LastError} = "Dimmer status should be between 0 (=0% or OFF) and 100 (=100% or ON)!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($DimmerName, $QBusChannelTypes{"DIMMER"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	$Status = Round($Status / 100 * 255, 0);
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetThermostatTempByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $ThermostatSetTemp;
	my $ThermostatTemp;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetThermostatTempByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetThermostatTempByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"SET_TEMP"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a thermostat!";
		return -1;
	};
	($ThermostatSetTemp, $ThermostatTemp) = $self->GetStatusByChannelID($ChannelID);
	if ($ThermostatTemp > 0)
	{
		$ThermostatTemp = $ThermostatTemp / 2;
	};
	return $ThermostatTemp;
}


sub GetThermostatSetTempByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $ThermostatSetTemp;
	my $ThermostatTemp;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetThermostatSetTempByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetThermostatSetTempByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"SET_TEMP"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a thermostat!";
		return -1;
	};
	($ThermostatSetTemp, $ThermostatTemp) = $self->GetStatusByChannelID($ChannelID);
	if ($ThermostatSetTemp > 0)
	{
		$ThermostatSetTemp = $ThermostatSetTemp / 2;
	};
	return $ThermostatSetTemp;
}


sub SetThermostatSetTempByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetThermostatSetTempByChannelID(\$ChannelID, \$ThermostatSetTemp)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $ThermostatSetTemp) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($ThermostatSetTemp)))
	{
		croak("Usage: SetThermostatSetTempByChannelID(\$ChannelID, \$ThermostatSetTemp)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!IsNumeric($ThermostatSetTemp))
	{
		$self->{LastError} = "Thermostat Set Temperature is not numeric!";
		return 0;
	};
	if (($ThermostatSetTemp < 0) || ($ThermostatSetTemp > 30))
	{
		$self->{LastError} = "Thermostat Set Temperature must be between 0 and 30°C!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"SET_TEMP"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a Thermostat!";
		return 0;
	};
	$ThermostatSetTemp = Round($ThermostatSetTemp * 2, 0);
	return $self->SetStatusByChannelID($ChannelID, $ThermostatSetTemp);
}


sub GetThermostatTempByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $ThermostatSetTemp;
	my $ThermostatTemp;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetThermostatTempByName(\$ThermostatName)") if @_ != 1;
	# Get the arguments
	my $ThermostatName = shift;
	# Check the arguments
	if (!defined($ThermostatName))
	{
		croak("Usage: GetThermostatTempByName(\$ThermostatName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($ThermostatName eq "")
	{
		$self->{LastError} = "Thermostat Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($ThermostatName, $QBusChannelTypes{"SET_TEMP"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	($ThermostatSetTemp, $ThermostatTemp) = $self->GetStatusByChannelID($ChannelID);
	if ($ThermostatTemp > 0)
	{
		$ThermostatTemp = $ThermostatTemp / 2;
	};
	return $ThermostatTemp;
}


sub GetThermostatSetTempByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $ThermostatSetTemp;
	my $ThermostatTemp;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetThermostatSetTempByName(\$ThermostatName)") if @_ != 1;
	# Get the arguments
	my $ThermostatName = shift;
	# Check the arguments
	if (!defined($ThermostatName))
	{
		croak("Usage: GetThermostatSetTempByName(\$ThermostatName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($ThermostatName eq "")
	{
		$self->{LastError} = "Thermostat Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($ThermostatName, $QBusChannelTypes{"SET_TEMP"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	($ThermostatSetTemp, $ThermostatTemp) = $self->GetStatusByChannelID($ChannelID);
	if ($ThermostatSetTemp > 0)
	{
		$ThermostatSetTemp = $ThermostatSetTemp / 2;
	};
	return $ThermostatSetTemp;
}


sub SetThermostatSetTempByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetThermostatSetTempByName(\$ThermostatName, \$ThermostatSetTemp)") if @_ != 2;
	# Get the arguments
	my ($ThermostatName, $ThermostatSetTemp) = @_;
	# Check the arguments
	if ((!defined($ThermostatName)) || (!defined($ThermostatSetTemp)))
	{
		croak("Usage: SetThermostatSetTempByName(\$ThermostatName, \$ThermostatSetTemp)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($ThermostatName eq "")
	{
		$self->{LastError} = "Thermostat Name not specified!";
		return 0;
	};
	if (!IsNumeric($ThermostatSetTemp))
	{
		$self->{LastError} = "Thermostat Set Temperature is not numeric!";
		return 0;
	};
	if (($ThermostatSetTemp < 0) || ($ThermostatSetTemp > 30))
	{
		$self->{LastError} = "Thermostat Set Temperature should be between 0 and 30°C!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($ThermostatName, $QBusChannelTypes{"SET_TEMP"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	$ThermostatSetTemp = Round($ThermostatSetTemp * 2, 0);
	return $self->SetStatusByChannelID($ChannelID, $ThermostatSetTemp);
}


sub GetThermostatProgByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetThermostatProgByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetThermostatProgByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"PROG_TEMP"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a thermostat program!";
		return -1;
	};
	return $self->GetStatusByChannelID($ChannelID);
}


sub SetThermostatProgByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetThermostatProgByChannelID(\$ChannelID, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $Status) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($Status)))
	{
		croak("Usage: SetThermostatProgByChannelID(\$ChannelID, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Thermostat Program is not numeric!";
		return 0;
	};
	if (($Status < 0) || ($Status > 4))
	{
		$self->{LastError} = "Thermostat Program should be between 0 and 4!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"PROG_TEMP"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a Thermostat Program!";
		return 0;
	};
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetThermostatProgByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetThermostatProgByName(\$ThermostatName)") if @_ != 1;
	# Get the arguments
	my $ThermostatName = shift;
	# Check the arguments
	if (!defined($ThermostatName))
	{
		croak("Usage: GetThermostatProgByName(\$ThermostatName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($ThermostatName eq "")
	{
		$self->{LastError} = "Thermostat Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($ThermostatName, $QBusChannelTypes{"PROG_TEMP"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	return $Status;
}


sub SetThermostatProgByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetThermostatProgByName(\$ThermostatName, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ThermostatName, $Status) = @_;
	# Check the arguments
	if ((!defined($ThermostatName)) || (!defined($Status)))
	{
		croak("Usage: SetThermostatProgByName(\$ThermostatName, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($ThermostatName eq "")
	{
		$self->{LastError} = "Thermostat Name not specified!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Thermostat Program is not numeric!";
		return 0;
	};
	if (($Status < 0) || ($Status > 4))
	{
		$self->{LastError} = "Thermostat Program should be between 0 and 4!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($ThermostatName, $QBusChannelTypes{"PROG_TEMP"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetShutterStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetShuttersStatusByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetShuttersStatusByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"SHUTTERS"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a Shutter!";
		return -1;
	};
	return $self->GetStatusByChannelID($ChannelID);
}


sub SetShutterStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetShutterStatusByChannelID(\$ChannelID, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $Status) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($Status)))
	{
		croak("Usage: SetShutterStatusByChannelID(\$ChannelID, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Shutter status is not numeric!";
		return 0;
	};
	if (($Status != 0) && ($Status != 1) && ($Status != 2))
	{
		$self->{LastError} = "Shutter status should be 0 (=Stop), 1 (=Up) or 2 (=Down)!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"SHUTTERS"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a shutter!";
		return 0;
	};
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetShutterStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetShutterStatusByName(\$ShutterName)") if @_ != 1;
	# Get the arguments
	my $ShutterName = shift;
	# Check the arguments
	if (!defined($ShutterName))
	{
		croak("Usage: GetShutterStatusByName(\$ShutterName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($ShutterName eq "")
	{
		$self->{LastError} = "Shutter Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($ShutterName, $QBusChannelTypes{"SHUTTERS"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	return $self->GetStatusByChannelID($ChannelID);
}


sub SetShutterStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetShutterStatusByName(\$ShutterName, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ShutterName, $Status) = @_;
	# Check the arguments
	if ((!defined($ShutterName)) || (!defined($Status)))
	{
		croak("Usage: SetShutterStatusByName(\$ShutterName, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($ShutterName eq "")
	{
		$self->{LastError} = "Shutter Name not specified!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Shutter status is not numeric!";
		return 0;
	};
	if (($Status != 0) && ($Status != 1) && ($Status != 2))
	{
		$self->{LastError} = "Shutter status should be 0 (=Stop), 1 (=Up) or 2 (=Down)!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($ShutterName, $QBusChannelTypes{"SHUTTERS"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetShutterPStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetShutterPStatusByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: GetShutterPStatusByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return -1;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return -1;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return -1;
	};
	if ($ChannelType != $QBusChannelTypes{"DIMMER"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a shutter with positioning!";
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	if ($Status > 0)
	{
		$Status = Round($Status / 255 * 100, 0);

	};
	return $Status;
}


sub SetShutterPStatusByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetShutterPStatusByChannelID(\$ChannelID, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ChannelID, $Status) = @_;
	# Check the arguments
	if ((!defined($ChannelID)) || (!defined($Status)))
	{
		croak("Usage: SetShutterPStatusByChannelID(\$ChannelID, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Shutter status is not numeric!";
		return 0;
	};
	if (($Status < 0) || ($Status > 100))
	{
		$self->{LastError} = "Shutter status should be between 0 (=0% or Down) and 100 (=100% or Up)!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"DIMMER"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a shutter with positioning!";
		return -1;
	};
	$Status = Round($Status / 100 * 255, 0);
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub GetShutterPStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;
	my $Status;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: GetShutterPStatusByName(\$ShutterName)") if @_ != 1;
	# Get the arguments
	my $ShutterName = shift;
	# Check the arguments
	if (!defined($ShutterName))
	{
		croak("Usage: GetShutterPStatusByName(\$ShutterName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return -1;
	};
	if ($ShutterName eq "")
	{
		$self->{LastError} = "Shutter Name not specified!";
		return -1;
	};
	if (!$self->GetChannelInfoByName($ShutterName, $QBusChannelTypes{"DIMMER"}, \$ChannelID, \$ChannelValue))
	{
		return -1;
	};
	$Status = $self->GetStatusByChannelID($ChannelID);
	if ($Status > 0)
	{
		$Status = Round($Status / 255 * 100, 0);
	};
	return $Status;
}


sub SetShutterPStatusByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: SetShutterPStatusByName(\$ShutterName, \$Status)") if @_ != 2;
	# Get the arguments
	my ($ShutterName, $Status) = @_;
	# Check the arguments
	if ((!defined($ShutterName)) || (!defined($Status)))
	{
		croak("Usage: SetShutterPStatusByName(\$ShutterName, \$Status)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($ShutterName eq "")
	{
		$self->{LastError} = "Shutter Name not specified!";
		return 0;
	};
	if (!IsNumeric($Status))
	{
		$self->{LastError} = "Shutter status is not numeric!";
		return 0;
	};
	if (($Status < 0) || ($Status > 100))
	{
		$self->{LastError} = "Shutter status should be between 0 (=0% or Down) and 100 (=100% or Up)!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($ShutterName, $QBusChannelTypes{"DIMMER"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	$Status = Round($Status / 100 * 255, 0);
	return $self->SetStatusByChannelID($ChannelID, $Status);
}


sub ActivateSceneByChannelID
{
	my $self = shift;
	my $ChannelName;
	my $ChannelType;
	my $ChannelValue;

	# Initialize objects and variables
	$self->{LastError} = "";

	# Check the number of arguments
	croak("Usage: ActivateSceneByChannelID(\$ChannelID)") if @_ != 1;
	# Get the arguments
	my $ChannelID = shift;
	# Check the arguments
	if (!defined($ChannelID))
	{
		croak("Usage: ActivateSceneByChannelID(\$ChannelID)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if (!IsNumeric($ChannelID))
	{
		$self->{LastError} = "ChannelID is not numeric!";
		return 0;
	};
	if ($ChannelID <= 0)
	{
		$self->{LastError} = "ChannelID must be > 0!";
		return 0;
	};
	if (!$self->GetChannelInfoByID($ChannelID, \$ChannelName, \$ChannelType, \$ChannelValue))
	{
		return 0;
	};
	if ($ChannelType != $QBusChannelTypes{"SCENES"})
	{
		$self->{LastError} = "ChannelID $ChannelID (\"$ChannelName\") is not a scene!";
		return 0;
	};
	return $self->SetStatusByChannelID($ChannelID, 0);
}


sub ActivateSceneByName
{
	my $self = shift;
	my $ChannelID;
	my $ChannelValue;

	# Check the number of arguments
	croak("Usage: ActivateSceneByName(\$SceneName)") if @_ != 1;
	# Get the arguments
	my $SceneName = shift;
	# Check the arguments
	if (!defined($SceneName))
	{
		croak("Usage: ActivateSceneByName(\$SceneName)");
	};
	if (!$self->{Connected})
	{
		$self->{LastError} = "Please login first using Connect()!";
		return 0;
	};
	if ($SceneName eq "")
	{
		$self->{LastError} = "Shutter Name not specified!";
		return 0;
	};
	if (!$self->GetChannelInfoByName($SceneName, $QBusChannelTypes{"SCENES"}, \$ChannelID, \$ChannelValue))
	{
		return 0;
	};
	return $self->SetStatusByChannelID($ChannelID, 0);
}

sub GetCTLErrorDescription
{
	my $ErrorNo = shift;
	
	if (!defined($ErrorNo))
	{
		croak("Usage: GetCTLErrorDescription(\$ErrorNo)");
	};
	switch($ErrorNo)
	{
		case 1		{ return "The controller is busy, please try again later!"; }
		case 2		{ return "Your session timed out. Please login again!"; }
		case 3		{ return "Too many devices are connected to the controller!"; }
		case 4		{ return "The controller was unable to execute your command!"; }
		case 5		{ return "Your session could not be started!"; }
		case 6		{ return "The command is unknown!"; }
		case 7		{ return "No EQOweb configuration found, please run System manager to upload and configure EQOweb!"; }
		case 8		{ return "System manager is still connected. Please close System manager to continue!"; }
		case 255	{ return "Undefined error in the controller! Please try again later!"; }
		else
		{
			return "Unknown error ($ErrorNo)!";
		}
	};
}

1;
