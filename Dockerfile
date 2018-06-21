FROM ubuntu:17.10

### SYSTEM DEPENDENCIES

# Everything from `make` onwards in apt-get install is only installed to ensure
# Python support works with all packages (which may require specific libraries
# at install time).
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
      make \
      libssl-dev \
      libbz2-dev \
      libreadline-dev \
      libsqlite3-dev \
      llvm \
      libncurses5-dev \
      libncursesw5-dev \
      libmysqlclient-dev \
      xz-utils \
      tk-dev \
    && locale-gen en_US.UTF-8
ENV LC_ALL en_US.UTF-8


### RUBY

# Install Ruby 2.5, update RubyGems, and install Bundler
RUN apt-key adv --keyserver keyserver.ubuntu.com --recv-keys C3173AA6 \
    && echo "deb http://ppa.launchpad.net/brightbox/ruby-ng/ubuntu artful main" > /etc/apt/sources.list.d/brightbox.list \
    && apt-get update \
    && apt-get install -y ruby2.5 ruby2.5-dev \
    && gem update --system 2.7.7 \
    && gem install --no-ri --no-rdoc bundler -v 1.16.2


### PYTHON

# Install Python 2.7 and 3.6 with pyenv. Using pyenv lets us support multiple Pythons
RUN git clone https://github.com/pyenv/pyenv.git /usr/local/.pyenv
ENV PYENV_ROOT=/usr/local/.pyenv
ENV PATH="$PYENV_ROOT/bin:$PATH"
RUN pyenv install 3.6.5 && pyenv install 2.7.14 && pyenv global 3.6.5


### JAVASCRIPT

# Install Node 8.0 and Yarn
RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get install -y nodejs \
    && curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - \
    && echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list \
    && apt-get update && apt-get install -y yarn


### PHP

# Install PHP 7.2 and Composer
RUN echo "deb http://ppa.launchpad.net/ondrej/php/ubuntu artful main" >> /etc/apt/sources.list.d/ondrej-php.list \
    && echo "deb-src http://ppa.launchpad.net/ondrej/php/ubuntu artful main" >> /etc/apt/sources.list.d/ondrej-php.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 4F4EA0AAE5267A6C \
    && apt-get update \
    && apt-get install -y php7.2 php7.2-xml php7.2-json php7.2-zip php7.2-mbstring php7.2-intl php7.2-common php7.2-gettext php7.2-curl php-xdebug php7.2-bcmath \
    && curl -sS https://getcomposer.org/installer | php \
    && mv composer.phar /usr/local/bin/composer


### Elixir

RUN wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb && dpkg -i erlang-solutions_1.0_all.deb \
    && apt-get update \
    && apt-get install -y esl-erlang \
    && wget https://github.com/elixir-lang/elixir/releases/download/v1.6.6/Precompiled.zip \
    && unzip -d /usr/local/elixir -x Precompiled.zip \
    && rm -f Precompiled.zip
ENV PATH="$PATH:/usr/local/elixir/bin"
RUN mix local.hex --force


### Rust

ENV RUSTUP_HOME=/opt/rust
RUN export CARGO_HOME=/opt/rust ; curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="${PATH}:/opt/rust/bin"


### Java, Groovy and Gradle

RUN echo "oracle-java8-installer shared/accepted-oracle-license-v1-1 select true" | debconf-set-selections \
    && echo "deb http://ppa.launchpad.net/webupd8team/java/ubuntu artful main" > /etc/apt/sources.list.d/webupd8team-java-trusty.list \
    && apt-key adv --keyserver keyserver.ubuntu.com --recv-keys EEA14886 \
    && apt-get update \
    && apt-get install -y oracle-java8-installer oracle-java8-set-default \
    && cd /tmp \
    && wget http://dl.bintray.com/groovy/maven/apache-groovy-binary-2.5.0.zip \
    && unzip apache-groovy-binary-2.5.0.zip \
    && mv groovy-2.5.0 /usr/local/groovy \
    && rm -f apache-groovy-binary-2.5.0.zip \
    && cd /tmp \
    && wget https://services.gradle.org/distributions/gradle-4.7-bin.zip \
    && unzip gradle-4.7-bin.zip \
    && mv gradle-4.7 /usr/local/gradle \
    && rm -f gradle-4.7-bin.zip
ENV JAVA_HOME=/usr/lib/jvm/java-8-oracle \
    GROOVY_HOME=/usr/local/groovy \
    GRADLE_HOME=/usr/local/gradle \
    PATH=/usr/local/groovy/bin/:/usr/local/gradle/bin:$PATH
