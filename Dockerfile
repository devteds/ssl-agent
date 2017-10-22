FROM ruby:2.3

RUN mkdir -p /ssl-agent/home
RUN mkdir -p /ssl-agent/certs
RUN mkdir -p /ssl-agent/webserver-root

WORKDIR /ssl-agent/home

VOLUME ["/ssl-agent/certs", "/ssl-agent/webserver-root"]

COPY ./Gemfile /ssl-agent/home/Gemfile
COPY ./Gemfile.lock /ssl-agent/home/Gemfile.lock

RUN bundle install

COPY ./acme-agent.rb /ssl-agent/home/acme-agent.rb
COPY ./entrypoint.sh /ssl-agent/home/entrypoint.sh

ENTRYPOINT ["/ssl-agent/home/entrypoint.sh"]

CMD ["info"]
