FROM ruby:2.5.3-slim
LABEL Description="Splay - Controller - Master process orchestrating Daemons and assigning jobs"

RUN mkdir -p /usr/splay

WORKDIR /usr/splay

RUN apt-get update -qq && apt-get -y --no-install-recommends install libgmp-dev \
    build-essential rubygems less mysql-client default-libmysqlclient-dev libssl-dev openssl


COPY Gemfile ./

RUN bundle install

COPY *.rb ./
COPY lib ./lib
COPY deploy_controller.sh .

# For testing the lib
COPY tests ./tests

RUN mkdir -p links

CMD ["./deploy_controller.sh"]
