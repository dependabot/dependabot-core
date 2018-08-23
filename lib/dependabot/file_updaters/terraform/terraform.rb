# frozen_string_literal: true

require "docker_registry2"

require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module FileUpdaters
    module Terraform
      class Terraform < Dependabot::FileUpdaters::Base
        def self.updated_files_regex
          [/\.tf$/]
        end

        def updated_dependency_files
          updated_files = []

          terraform_files.each do |file|
            next unless file_changed?(file)

            updated_content = updated_terraform_file_content(file)
            raise "Content didn't change!" if updated_content == file.content

            updated_files << updated_file(file: file, content: updated_content)
          end

          raise "No files changed!" if updated_files.none?

          updated_files
        end

        private

        # rubocop:disable Metrics/AbcSize
        def updated_terraform_file_content(file)
          updated_content = file.content.dup

          reqs = dependency.requirements.zip(dependency.previous_requirements).
                 reject { |new_req, old_req| new_req == old_req }

          # Loop through each changed requirement and update the pomfiles
          reqs.each do |new_req, old_req|
            raise "Bad req match" unless new_req[:file] == old_req[:file]
            next unless new_req.fetch(:file) == file.name

            # TODO: Handle non-git requirements
            raise "Not a git req!" if new_req[:source][:type] != "git"

            url = old_req.fetch(:source)[:url].gsub(%r{^https://}, "")
            tag = old_req.fetch(:source)[:ref]
            url_regex = /#{Regexp.quote(url)}.*ref=#{Regexp.quote(tag)}/

            updated_content.sub!(url_regex) do |url_match|
              url_match.sub(old_req[:source][:ref], new_req[:source][:ref])
            end
          end

          updated_content
        end
        # rubocop:enable Metrics/AbcSize

        def dependency
          # Terraform updates will only ever be updating a single dependency
          dependencies.first
        end

        def files_with_requirement
          filenames = dependency.requirements.map { |r| r[:file] }
          dependency_files.select { |file| filenames.include?(file.name) }
        end

        def terraform_files
          dependency_files.select { |f| f.name.end_with?(".tf") }
        end

        def check_required_files
          return if terraform_files.any?
          raise "No Terraform configuration file!"
        end
      end
    end
  end
end
