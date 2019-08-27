FROM hashicorp/consul-template:0.21.0-scratch as consul-template
FROM glorpen/puppetizer-base:2.3.2-alpine3.10-6.6.0

LABEL maintainer="Arkadiusz Dzięgiel <arkadiusz.dziegiel@glorpen.pl>"

COPY --from=consul-template /consul-template /usr/local/bin/
COPY ./puppetizer/Puppetfile /opt/puppetizer/etc/puppet/puppetfile

RUN /opt/puppetizer/bin/update-modules

COPY ./puppetizer/hiera/ /opt/puppetizer/puppet/hiera/
ADD ./puppetizer/code /opt/puppetizer/puppet/modules/puppetizer_main

RUN /opt/puppetizer/bin/build
