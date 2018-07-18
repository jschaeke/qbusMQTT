FROM arm64v8/perl:latest

RUN cpanm LWP::UserAgent \
          HTTP::Cookies \
          HTTP::Request::Common \
          JSON \
          Data::Dumper \
          Carp \
          Switch \
          Module::Build \
          inc::latest \
          WebSphere::MQTT::Client \
          Config::Simple \
          FindBin::libs \
          forks \
           && rm -rf /root/.cpanm 

COPY . /usr/src/qbusMQTTbridge
WORKDIR /usr/src/qbusMQTTbridge

CMD [ "perl", "./qbusMQTTbridge.pm" ]
