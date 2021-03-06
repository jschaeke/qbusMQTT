# QbusMQTT
A Qbus EQOweb to MQTT bridge

# Purpose
This perl script acts a bridge between an MQTT broker and a Qbus home automation system (Eqoweb).
By doing so, Qbus can be integrated into a home automation solution such as Domogik, OpenHab or Domoticz
Also interesting is Node-RED to easily setup flows with other online services like IFTTT, PushOver, Alexa.

# Future
No intention to continue on this project. I switched over to a Node.js implementation https://github.com/jschaeke/qbusMqtt2. 

# Documentation
None so far, just this readme.
Each device is referenced by its channelId on a MQTT topic such as qbus/1. There's only one topic per device and it's
bi-directional: Qbus state changes are published to MQTT but also MQTT messages on the device topic can
trigger a Qbus change. However, in case the device state remains the same or when it's part of the excludedDevices array,
the message is filtered out.

# Current state
This code has been running for year without stability or memory issues. I personally don't have Qbus hardware and didn't spend all too much time in it; it needs cleaning like removal of print statements.
Notice there's a delay from EQOweb to mqtt due to the fact EQOweb is polled.

# Thanks
I want to thank Bart Boelaert for publishing the initial library I've included into this project (http://bartboelaert.blogspot.be/2015/01/interfacing-qbus-building-intelligence.html).
Sorry Bart if I messed it up, I am not a perl coder. This was just a little project to help a friend with a Qbus installation.

# Installation
Create a qbusMQTT.ini with the properties of the MQTT broker (e.g. Mosquitto) and Eqoweb (example provided).
Either build an image with Docker (provided example starts from arm64v8 architecture) or install perl with all the necessary dependencies with the instructions below.

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
install fork
install FindBin::lib
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
