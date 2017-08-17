# QbusMQTT
A Qbus EQOweb to MQTT bridge

# Purpose
This perl script acts a bridge between an MQTT broker and a Qbus home automation system (Eqoweb). 
By doing so, Qbus can be integrated into home automation software solutions such as Domogik, OpenHab or Domoticz.
Or with Node-RED logic can be programmed with flows and other online services can be wired such as IFTTT, PushOver, Alexa.

# Documentation
None so far, just this readme.
Each device is referenced by its channelId on a MQTT topic such as qbus/1. There's only one topic per device and it's
bi-directional: Qbus state changes are published to MQTT but also MQTT messages on the device topic can
trigger a Qbus change. However, in case the device state remains the same or when it's part of the excludedDevices array,
the message is filtered out.

# Current state
This code has not been thoroughly tested yet as I personally don't have Qbus hardware, it needs cleaning such as removal of print statements. 
So far I've heard it runs quite stable but it seems a keep-alive request need to be sent to assure the connection remains open (otherwise a delay
upon a request to QBus can be encountered). 

# Thanks
I want to thank Bart Boelaert for publishing the initial library I've included into this project (http://bartboelaert.blogspot.be/2015/01/interfacing-qbus-building-intelligence.html). 
Sorry Bart if I messed it up, I am not a perl coder. This was just a little project to help a friend with a Qbus installation.

# Installation
Install perl with all the necessary dependencies, create a qbusMQTT.ini with the properties of the MQTT broker (e.g. Mosquitto) and Eqoweb (example provided).

## Install instructions for Perl dependencies
```bash
sudo perl -MCPAN -eshell
```
```perl5
install LWP::UserAgent
install HTTP::Cookies
install HTTP::Request::Common
install JSON
install Data::Dumper
install Carp
install Switch
install Module::Build
install inc::latest
install WebSphere::MQTT::Client
install Config::Simple
```

## Autostart in Ubuntu
```bash
chmod +x ./qbusMQTTbridge.pm
cp qbusMQTT_init.d /etc/init.d/qbusMQTT
chmod +x /etc/init.d/qbusMQTT
sudo chown root:root /etc/init.d/qbusMQTT
sudo chmod 755 /etc/init.d/qbusMQTT
cd /etc/init.d
sudo update-rc.d qbusMqtt defaults 97 03
sudo update-rc.d qbusMqtt enable
```

# Future
Rewrite to node.js
