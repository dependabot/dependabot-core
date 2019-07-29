# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/puppet/r10k/puppetfile"
require "dependabot/puppet/r10k/module/forge"

module Dependabot
  module Puppet
    class FileParser < Dependabot::FileParsers::Base
      def parse
        dependency_set = Dependabot::FileParsers::Base::DependencySet.new
        parsed = Dependabot::Puppet::Puppetfile::R10K::Puppetfile.new
        parsed.load!(puppet_file.content)

        parsed.modules.keep_if{|m| m.is_a?(
          Dependabot::Puppet::Puppetfile::R10K::Module::Forge
        )}
        parsed.modules.each do |puppet_module|
          dep = Dependency.new(
            name:            puppet_module.name,
            version:         puppet_module.version,
            package_manager: "puppet",
            requirements:    [{
              requirement: puppet_module.version,
              file: puppet_file.name,
              source: {
                type: "default",
                source: puppet_module.title
              },
              groups: []
            }],
          )
          dependency_set << dep
        end

        dependency_set.dependencies
      end

      private
      def check_required_files
        raise "No Puppetfile!" unless puppet_file
      end

      def puppet_file
        @puppet_file ||= get_original_file("Puppetfile")
      end
    end
  end
end

Dependabot::FileParsers.
  register("puppet", Dependabot::Puppet::FileParser)
