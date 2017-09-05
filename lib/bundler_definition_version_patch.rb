# frozen_string_literal: true
require "bundler/vendored_persistent"

# rubocop:disable all
# TODO: Remove when 1.16.0.pre.2
module Bundler
  class PersistentHTTP < Persistent::Net::HTTP::Persistent
    def warn_old_tls_version_rubygems_connection(uri, connection)
      return unless connection.use_ssl?
      return unless (uri.host || "").end_with?("rubygems.org")

      socket = connection.instance_variable_get(:@socket)
      socket_io = socket&.io
      return unless socket_io.respond_to?(:ssl_version)
      ssl_version = socket_io.ssl_version

      case ssl_version
      when /TLSv([\d\.]+)/
        version = Gem::Version.new($1)
        if version < Gem::Version.new("1.2")
          Bundler.ui.warn \
            "Warning: Your Ruby version is compiled against a copy of OpenSSL that is very old. " \
            "Starting in January 2018, RubyGems.org will refuse connection requests from these " \
            "very old versions of OpenSSL. If you will need to continue installing gems after " \
            "January 2018, please follow this guide to upgrade: http://ruby.to/tls-outdated.",
            :wrap => true
        end
      end
    end
  end
end
# rubocop:enable

module BundlerDefinitionVersionPatch
  def index
    @index ||= super.tap do |index|
      if ruby_version
        requested_version = ruby_version.to_gem_version_with_patchlevel
        sources.metadata_source.specs <<
          Gem::Specification.new("ruby\0", requested_version)
      end
    end
  end
end
Bundler::Definition.prepend(BundlerDefinitionVersionPatch)
