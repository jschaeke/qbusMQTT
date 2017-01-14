# QbusMQTT
A Qbus EQOweb to MQTT bridge

#Purpose
This perl script acts a bridge between an MQTT broker and a Qbus home automation system (Eqoweb). By doing so, Qbus can be integrated into home automation software solutions such as Domogik, OpenHab, Domoticz,... 

#Documentation
None so far

#Installation
Install perl with all the necessary dependencies, create a qbusMQTT.ini with the properties of the MQTT broker (e.g. Mosquitto) and Eqoweb.

#Current state
The code has not been thoroughly tested yet, it needs cleaning such as removal of print statements.

#Thanks
I want to thank Bart Boelaert for publishing the initial library I've included into this project (http://bartboelaert.blogspot.be/2015/01/interfacing-qbus-building-intelligence.html). Sorry Bart if I messed it up, I am not a perl coder. This was just a little project to help a friend with a Qbus installation..

#Perl dependencies
    sudo perl -MCPAN -eshell
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

#Autostart ubuntu
	chmod +x ./qbusMQTTbridge.pm
	cp qbusMQTT_init.d /etc/init.d/qbusMQTT
	chmod +x /etc/init.d/qbusMQTT
	sudo update-rc.d qbusMQTT defaults