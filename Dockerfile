FROM glorpen/puppet-base:centos7

LABEL maintainer="Arkadiusz Dzięgiel <arkadiusz.dziegiel@glorpen.pl>"
LABEL eu.glorpen.puppetizer.builder="1.0.0"

ADD ./puppetizer /opt/puppetizer/sources/main

RUN /opt/puppetizer/bin/build
