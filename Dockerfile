FROM ruby:2.2.3

RUN apt-get update -qq && apt-get install -y build-essential

# Needed to clone GitHub repos without interactive prompts
RUN mkdir -p /root/.ssh/ && ssh-keyscan github.com > /root/.ssh/github.pub
# Verify RSA identity of github.com
RUN [ "$(ssh-keygen -lf /root/.ssh/github.pub | awk '{print $2}')" = "16:27:ac:a5:76:28:2d:36:63:1b:56:4d:eb:df:a6:48" ] && \
    mv /root/.ssh/github.pub /root/.ssh/known_hosts || (echo "Wrong Github Fingerprint" && exit 1)

ENV APP_HOME /app
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

ADD Gemfile* $APP_HOME/

ENV BUNDLE_GEMFILE=$APP_HOME/Gemfile \
  BUNDLE_JOBS=2 \
  BUNDLE_PATH=/bundle

RUN bundle install

ADD . $APP_HOME
