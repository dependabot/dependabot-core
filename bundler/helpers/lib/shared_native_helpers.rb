# frozen_string_literal: true

require "excon"

module SharedNativeHelpers
  USER_AGENT = "dependabot-core/bundler-helper "\
               "#{Excon::USER_AGENT} ruby/#{RUBY_VERSION} "\
               "(#{RUBY_PLATFORM}) "\
               "(+https://github.com/dependabot/dependabot-core)"

  def self.excon_middleware
    Excon.defaults[:middlewares] +
      [Excon::Middleware::Decompress] +
      [Excon::Middleware::RedirectFollower]
  end

  def self.excon_headers(headers = nil)
    headers ||= {}
    {
      "User-Agent" => USER_AGENT
    }.merge(headers)
  end

  # Duplicated in common/lib/dependabot/shared_helpers.rb
  def self.excon_defaults(options = nil)
    options ||= {}
    headers = options.delete(:headers)
    {
      connect_timeout: 5,
      write_timeout: 5,
      read_timeout: 20,
      omit_default_port: true,
      middlewares: excon_middleware,
      headers: excon_headers(headers)
    }.merge(options)
  end
end
