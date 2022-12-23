# frozen_string_literal: true

require "dependabot/docker/utils/helpers"
require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"

module Dependabot
  module Docker
    class FileUpdater < Dependabot::FileUpdaters::Base
      FROM_REGEX = /FROM(\s+--platform\=\S+)?/i

      def self.updated_files_regex
        [
          /dockerfile/i,
          /^[^\.]+\.ya?ml/i
        ]
      end

      def updated_dependency_files
        updated_files = []
        dependency_files.each do |file|
          next unless requirement_changed?(file, dependency)

          updated_files << if file.name.match?(/^[^\.]+\.ya?ml/i)
                             updated_file(
                               file: file,
                               content: updated_yaml_content(file)
                             )
                           else
                             updated_file(
                               file: file,
                               content: updated_dockerfile_content(file)
                             )
                           end
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      def dependency
        # Dockerfiles will only ever be updating a single dependency
        dependencies.first
      end

      def check_required_files
        # Just check if there are any files at all.
        return if dependency_files.any?

        raise "No Dockerfile!"
      end

      def updated_dockerfile_content(file)
        updated_content =
          if specified_with_digest?(file)
            update_digest_and_tag(file)
          else
            update_tag(file)
          end

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      def update_digest_and_tag(file)
        old_declaration_regex = /^#{FROM_REGEX}\s+.*@#{old_digest(file)}/

        file.content.gsub(old_declaration_regex) do |old_dec|
          old_dec.
            gsub("@#{old_digest(file)}", "@#{new_digest(file)}").
            gsub(":#{dependency.previous_version}",
                 ":#{dependency.version}")
        end
      end

      def update_tag(file)
        old_tags = old_tags(file)
        return if old_tags.empty?

        modified_content = file.content

        new_tags = new_tags(file)

        old_tags.zip(new_tags).each do |old_tag, new_tag|
          new_tag ||= new_tags.first

          old_declaration =
            if private_registry_url(file) then "#{private_registry_url(file)}/"
            else
              ""
            end
          old_declaration += "#{dependency.name}:#{old_tag}"
          escaped_declaration = Regexp.escape(old_declaration)

          old_declaration_regex =
            %r{^#{FROM_REGEX}\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)}

          modified_content = modified_content.
                             gsub(old_declaration_regex) do |old_dec|
            old_dec.gsub(":#{old_tag}", ":#{new_tag}")
          end
        end

        modified_content
      end

      def specified_with_digest?(file)
        dependency.
          requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source)[:digest]
      end

      def new_digest(file)
        return unless specified_with_digest?(file)

        dependency.requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source).fetch(:digest)
      end

      def old_digest(file)
        return unless specified_with_digest?(file)

        dependency.previous_requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source).fetch(:digest)
      end

      def new_tags(file)
        dependency.requirements.
          select { |r| r[:file] == file.name }.
          map { |r| r.fetch(:source)[:tag] }
      end

      def old_tags(file)
        dependency.
          previous_requirements.
          select { |r| r[:file] == file.name }.
          map { |r| r.fetch(:source)[:tag] }
      end

      def private_registry_url(file)
        dependency.requirements.
          find { |r| r[:file] == file.name }.
          fetch(:source)[:registry]
      end

      def updated_yaml_content(file)
        updated_content = Utils.likely_helm_chart?(file) ? update_helm(file) : update_image(file)

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      def update_helm(file)
        # TODO: this won't work if two images have the same tag version
        old_tags = old_helm_tags(file)
        return if old_tags.empty?

        modified_content = file.content

        old_tags.each do |old_tag|
          old_tag_regex = /^\s+(?:-\s)?(?:tag|version):\s+["']?#{old_tag}["']?(?=\s|$)/
          modified_content = modified_content.gsub(old_tag_regex) do |old_img_tag|
            old_img_tag.gsub(old_tag.to_s, new_yaml_tag(file).to_s)
          end
        end
        modified_content
      end

      def update_image(file)
        old_images = old_yaml_images(file)
        return if old_images.empty?

        modified_content = file.content

        old_images.each do |old_image|
          old_image_regex = /^\s+(?:-\s)?image:\s+#{old_image}(?=\s|$)/
          modified_content = modified_content.gsub(old_image_regex) do |old_img|
            old_img.gsub(old_image.to_s, new_yaml_image(file).to_s)
          end
        end
        modified_content
      end

      def new_yaml_image(file)
        element = dependency.requirements.find { |r| r[:file] == file.name }
        prefix = element.fetch(:source)[:registry] ? "#{element.fetch(:source)[:registry]}/" : ""
        digest = element.fetch(:source)[:digest] ? "@#{element.fetch(:source)[:digest]}" : ""
        tag = element.fetch(:source)[:tag] ? ":#{element.fetch(:source)[:tag]}" : ""
        "#{prefix}#{dependency.name}#{tag}#{digest}"
      end

      def new_yaml_tag(file)
        element = dependency.requirements.find { |r| r[:file] == file.name }
        element.fetch(:source)[:tag] || ""
      end

      def old_yaml_images(file)
        dependency.
          previous_requirements.
          select { |r| r[:file] == file.name }.map do |r|
            prefix = r.fetch(:source)[:registry] ? "#{r.fetch(:source)[:registry]}/" : ""
            digest = r.fetch(:source)[:digest] ? "@#{r.fetch(:source)[:digest]}" : ""
            tag = r.fetch(:source)[:tag] ? ":#{r.fetch(:source)[:tag]}" : ""
            "#{prefix}#{dependency.name}#{tag}#{digest}"
          end
      end

      def old_helm_tags(file)
        dependency.
          previous_requirements.
          select { |r| r[:file] == file.name }.map do |r|
            r.fetch(:source)[:tag] || ""
          end
      end
    end
  end
end

Dependabot::FileUpdaters.register("docker", Dependabot::Docker::FileUpdater)
