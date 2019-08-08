# frozen_string_literal: true

require "dependabot/puppet/file_updater"

module Dependabot
  module Puppet
    class FileUpdater
      class PuppetfileUpdater
        require_relative "git_pin_replacer"
        require_relative "git_source_remover"
        require_relative "requirement_replacer"

        def initialize(dependencies:, puppetfile:)
          @dependencies = dependencies
          @puppetfile = puppetfile
        end

        def updated_puppetfile_content
          content = puppetfile.content

          dependencies.each do |dependency|
            content = replace_puppetfile_version_requirement(
              dependency,
              puppetfile,
              content
            )

            if remove_git_source?(dependency)
              content = remove_puppetfile_git_source(dependency, content)
            end

            if update_git_pin?(dependency)
              content =
                update_puppetfile_git_pin(dependency, puppetfile, content)
            end
          end

          content
        end

        private

        attr_reader :dependencies, :puppetfile

        def replace_puppetfile_version_requirement(dependency, file, content)
          return content unless requirement_changed?(file, dependency)

          updated_requirement =
            dependency.requirements.
            find { |r| r[:file] == file.name }.
            fetch(:requirement)

          previous_requirement =
            dependency.previous_requirements.
            find { |r| r[:file] == file.name }.
            fetch(:requirement)

          RequirementReplacer.new(
            dependency: dependency,
            updated_requirement: updated_requirement,
            previous_requirement: previous_requirement,
            insert_if_bare: !updated_requirement.nil?
          ).rewrite(content)
        end

        def requirement_changed?(file, dependency)
          changed_requirements =
            dependency.requirements - dependency.previous_requirements

          changed_requirements.any? { |f| f[:file] == file.name }
        end

        def remove_git_source?(dependency)
          old_puppetfile_req =
            dependency.previous_requirements.
            find { |f| %w(Puppetfile).include?(f[:file]) }

          return false unless old_puppetfile_req&.dig(:source, :type) == "git"

          new_puppetfile_req =
            dependency.requirements.
            find { |f| %w(Puppetfile).include?(f[:file]) }

          new_puppetfile_req[:source].nil?
        end

        def update_git_pin?(dependency)
          new_puppetfile_req =
            dependency.requirements.
            find { |f| %w(Puppetfile).include?(f[:file]) }
          return false unless new_puppetfile_req&.dig(:source, :type) == "git"

          # If the new requirement is a git dependency with a ref then there's
          # no harm in doing an update
          new_puppetfile_req.dig(:source, :ref)
        end

        def remove_puppetfile_git_source(dependency, content)
          GitSourceRemover.new(dependency: dependency).rewrite(content)
        end

        def update_puppetfile_git_pin(dependency, file, content)
          new_pin =
            dependency.requirements.
            find { |f| f[:file] == file.name }.
            fetch(:source).fetch(:ref)

          GitPinReplacer.
            new(dependency: dependency, new_pin: new_pin).
            rewrite(content)
        end
      end
    end
  end
end
