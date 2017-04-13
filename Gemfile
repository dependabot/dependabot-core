# frozen_string_literal: true
ruby "2.3.3"
source "https://rubygems.org"

# Dependencies necessary for using bump as a library are in the gemspec
gemspec

# Dependencies necessary for running bump as an app are here
gem "prius", "~> 1.0.0"
gem "rake"
gem "sentry-raven", "~> 2.1.4"
gem "sidekiq", "~> 4.2.7"
gem "sinatra"

group :development do
  gem "dotenv", require: false
  gem "foreman", "~> 0.82.0"
  gem "highline", "~> 1.7.8"
  gem "rspec", "~> 3.5.0"
  gem "rspec-its", "~> 1.2.0"
  gem "rubocop", "~> 0.46.0"
  gem "webmock", "~> 2.3.1"
end
