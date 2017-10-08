# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Docker
      class Docker < Dependabot::FileParsers::Base
        # Detials of Docker regular expressions is at
        # https://github.com/docker/distribution/blob/master/reference/regexp.go
        DOMAIN_COMPONENT = /(?:[a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])/
        DOMAIN = /(?:#{DOMAIN_COMPONENT}(?:\.#{DOMAIN_COMPONENT})+)/
        REGISTRY = %r{(?<registry>#{DOMAIN}(?::[0-9]+)?)/}

        NAME_COMPONENT = /(?:[a-z0-9]+(?:(?:[._]|__|[-]*)[a-z0-9]+)*)/
        IMAGE = %r{(?<image>#{NAME_COMPONENT}(?:/#{NAME_COMPONENT})*)}

        FROM = /[Ff][Rr][Oo][Mm]/
        TAG = /:(?<tag>[\w][\w.-]{0,127})/
        DIGEST = /@(?<digest>[^\s]+)/
        NAME = /\s+AS\s+(?<name>[a-zA-Z0-9_-]+)/
        FROM_LINE = /^#{FROM}\s+#{REGISTRY}?#{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?/

        def parse
          dependencies = []

          dockerfile.content.each_line do |line|
            next unless FROM_LINE.match?(line)
            captures = FROM_LINE.match(line).named_captures

            # TODO: Support digests (need to extract the tag they relate to
            # from them, so we can compare it with other versions)
            version = captures.fetch("tag")
            next if version.nil?

            if captures.fetch("registry")
              raise PrivateSourceNotReachable, captures.fetch("registry")
            end

            dependencies << Dependency.new(
              name: captures.fetch("image"),
              version: version,
              package_manager: "docker",
              requirements: []
            )
          end

          dependencies
        end

        private

        def dockerfile
          @dockerfile ||= get_original_file("Dockerfile")
        end

        def check_required_files
          %w(Dockerfile).each do |filename|
            raise "No #{filename}!" unless get_original_file(filename)
          end
        end
      end
    end
  end
end
