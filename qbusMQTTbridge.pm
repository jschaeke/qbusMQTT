#! /usr/bin/perl -w
use strict;

use BB::Qbus::EQOweb;

use threads;
use threads::shared;
use JSON;
use WebSphere::MQTT::Client;
use Config::Simple;

#use Device::SerialPort;
use Time::HiRes qw(time);
use strict;
use POSIX;

my $objQbus;
my $ErrorDesc;
my $Status;

my $cfg = new Config::Simple('qbusMQTT.ini');

# mqtt configuration
my $mqtt_hostname = $cfg->param('MQTT.hostname');
my $mqtt_port     = $cfg->param('MQTT.port') + 0;
my $mqtt_topic    = $cfg->param('MQTT.topic');

my $qbus_max_devices = $cfg->param('EQOWeb.maxDevices') + 0;

my @state : shared      = (-1) x $qbus_max_devices;
my @deviceType : shared = (-1) x $qbus_max_devices;

# Test initialize
$objQbus = EQOweb->new(
	QbusCTLIP            => $cfg->param('EQOWeb.QbusCTLIP'),
	UserName             => $cfg->param('EQOWeb.userName'),
	Password             => $cfg->param('EQOWeb.password'),
	MaxReconnectAttempts => 3,
	Debug                => 0
);

# Test connect
unless ( $objQbus->Connect() ) {
	print( $objQbus->{LastError} . "\n" );
	exit 1;
}

my $mqtt = new WebSphere::MQTT::Client(
	Hostname   => $mqtt_hostname,
	Port       => $mqtt_port,
	clientid   => 'rf12_sender_mqtt',
	keep_alive => 15,
	async      => 1
);
my $mqtta = new WebSphere::MQTT::Client(
	Hostname   => $mqtt_hostname,
	Port       => $mqtt_port,
	clientid   => 'rf12_received_mqtt',
	keep_alive => 30,
	async      => 1
);

my %QBusChannelTypes = $objQbus->getChannelTypes();

# connect to MQTT server
my $res = $mqtt->connect();
die "Failed to connect: $res\n" if ($res);

my $ts;

sub sendMqtt {
	my ( $ChannelID, $Status, $devType ) = @_;
	$ts = time();

	#Set the device type
	if ( $devType > -1 ) {
		$deviceType[$ChannelID] = $devType;
	}
	##################CONVERSION
	my $convertedStatus = $Status;

	#print(" Channel " . $ChannelID . " : ");
	if ( $deviceType[$ChannelID] == $QBusChannelTypes{"TOGGLE"} ) {
		$convertedStatus = ceil( $Status / 255 );

	   #print(" converted toggle " . $Status . " -> " . $convertedStatus. "; ");
	}
	elsif ( $deviceType[$ChannelID] == $QBusChannelTypes{"DIMMER"} ) {
		$convertedStatus = floor( $Status / 2.55 );

	  #print(" converted dimmer " . $Status . " -> " . $convertedStatus . "; ");
	}
	else {
		#	print(" no conversion for " . $Status  );
	}
	if ( $state[$ChannelID] != $convertedStatus ) {
		my $mqtt_topic_channel = $mqtt_topic . $ChannelID;
		$mqtt->connect();
		print(  "QBUS->MQTT: "
			  . $mqtt_topic_channel . " "
			  . $convertedStatus
			  . "\n" );
		my $result = $mqtt->publish( $convertedStatus, $mqtt_topic_channel );

		if ( 'CONNECTION_BROKEN' eq $result ) {
			print('RECONNECT MQTT!!, recursive call');
			sleep(1);
			sendMqtt( $ChannelID, $Status, $devType );
		}
		else {
			lock(@state);
			$state[$ChannelID] = $convertedStatus;
		}
	}
	#print join(", ", @deviceType);
}

sub in {
	for ( ; ; ) {
		my @res = ();
		$Status = $objQbus->mapChannelInfo( \&sendMqtt );

		# if no message was sent each 5 seconds, just send a status message to keep us connected to the server
		if ( time() - $ts > 5 ) {

			#print("set status ");
			$mqtt->status();
			$ts = time();
		}
	}
}

sub out {
	# connect to mqtt server
	my $resa = $mqtta->connect();
	die "Failed to connect: $res\n" if ($res);

	$mqtta->subscribe( $mqtt_topic . "#" );
	my $tsa;

	my @resa             = ();
	my @QBusChannelTypes = ();
	for ( ; ; ) {
		eval {
			@resa = $mqtta->receivePub();

			#print Dumper(@resa);
			#print( 'we got ' . @resa  . ' ');
		};
		if ($@) {
			print( $@ . 'RECONNECTING!!' );
			print('RECONNECT MQTT!, recursive call');
			sleep(1);
			out();
			$@ = ();
		}
		my $topic = $resa[0];
		my $ChannelID = ( split '/', $topic )[-1];

		##################CONVERSION
		my $Status          = $resa[1];
		my $convertedStatus = $Status;

		if ( $deviceType[$ChannelID] == $QBusChannelTypes{"TOGGLE"} ) {
			$convertedStatus = floor( $Status * 255 );
			#print("in: converted toggle " . $Status . " -> " . $convertedStatus. "; ");
		}
		elsif ( $deviceType[$ChannelID] == $QBusChannelTypes{"DIMMER"} ) {
			$convertedStatus = ceil( $Status * 2.55 );
  		 	#print("in: converted dimmer " . $Status . " -> " . $convertedStatus . "; ");
		}
		if ( $state[$ChannelID] != $Status ) {
			print("MQTT->QBUS: " . $ChannelID . " " . $convertedStatus . "\n" );
			$Status = $objQbus->SetStatusByChannelID($ChannelID, $convertedStatus );
		}


		#Immediately broadcast updated status
		#
		#sendMqtt( $ChannelID, $convertedStatus, $deviceType[$ChannelID] );
		if ( $Status == -1 ) {
			print( $objQbus->{LastError} . "\n" );
		}
	}
}

#start both threads
my $thr1 = threads->new( \&in );
#Sleep to allow the state array to be populated
sleep(10);
my $thr2 = threads->new( \&out );
$thr1->join;
$thr2->join;
