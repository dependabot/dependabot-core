# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Docker
      class Docker < Dependabot::FileParsers::Base
        PATH = /[a-z0-9]+(?:[._-][a-z0-9]+)*/
        IMAGE = %r{(?<image>#{PATH}(?:/#{PATH})*)}
        TAG = /:(?<tag>[a-zA-Z0-9_]+[A-z0-9._-]*)/
        DIGEST = /@(?<digest>[0-9a-f]+)/
        NAME = / AS (?<name>[a-zA-Z0-9_-]+)/
        FROM_LINE = /^[Ff][Rr][Oo][Mm] #{IMAGE}#{TAG}?#{DIGEST}?#{NAME}?/

        def parse
          dependencies = []

          dockerfile.content.each_line do |line|
            next unless FROM_LINE.match?(line)
            captures = FROM_LINE.match(line).named_captures

            # TODO: Support digests (need to extract the tag they relate to
            # from them, so we can compare it with other versions)
            version = captures.fetch("tag")

            next if version.nil?

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
