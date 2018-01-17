FROM ubuntu:17.10

### SYSTEM DEPENDENCIES

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
      build-essential \
      dirmngr \
      git \
      curl \
      wget \
      zlib1g-dev \
      liblzma-dev \
      tzdata \
      zip \
      unzip \
      locales \
      openssh-client \
    && locale-gen en_US.UTF-8
ENV LC_ALL en_US.UTF-8


### RUBY

# Install Ruby 2.4, update RubyGems, and install Bundler
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C3173AA6 \
    && echo "deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu artful main" > /etc/apt/sources.list.d/brightbox.list \
    && apt-get update \
    && apt-get install -y ruby2.4 ruby2.4-dev \
    && gem update --system 2.7.4 \
    && gem install --no-ri --no-rdoc bundler -v 1.16.1


### PYTHON

# Install Python 3.6 and Pip
RUN apt-get install -y python3.6 python3.6-dev \
    && ln -s /usr/bin/python3.6 /usr/local/bin/python \
    && curl -s https://bootstrap.pypa.io/get-pip.py | python


### JAVASCRIPT

# Install Node 8.0 and Yarn
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get install -y nodejs \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update && apt-get install -y yarn


### PHP

# Install PHP 7.1 and Composer
RUN echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu artful main" >> /etc/apt/sources.list.d/ondrej-php.list \
    && echo "deb-src http://ppa.launchpad.net/ondrej/php/ubuntu artful main" >> /etc/apt/sources.list.d/ondrej-php.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C \
    && apt-get update \
    && apt-get install -y php7.1 php7.1-xml php7.1-zip \
    && curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer


### Elixir

RUN wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && dpkg -i erlang-solutions_1.0_all.deb \
    && apt-get update \
    && apt-get install -y esl-erlang \
    && wget https://github.com/elixir-lang/elixir/releases/download/v1.6.0/Precompiled.zip \
    && unzip -d /usr/local/elixir -x Precompiled.zip \
    && rm -f Precompiled.zip
ENV PATH="$PATH:/usr/local/elixir/bin"
RUN mix local.hex --force
