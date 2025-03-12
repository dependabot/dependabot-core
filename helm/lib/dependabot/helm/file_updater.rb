# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"
require "yaml"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      extend T::Sig
      extend T::Helpers

      CHART_YAML_REGEXP = /Chart\.ya?ml/i
      VALUES_YAML_REGEXP = /values(?>\.[\w-]+)?\.ya?ml/i
      YAML_REGEXP = /(Chart|values(?>\.[\w-]+)?)\.ya?ml/i
      IMAGE_REGEX = /(?:image:|repository:\s*)/i

      sig { override.returns(T::Array[Regexp]) }
      def self.updated_files_regex
        [CHART_YAML_REGEXP, VALUES_YAML_REGEXP]
      end

      sig { override.returns(String) }
      def file_type
        "Helm chart"
      end

      sig { override.returns(Regexp) }
      def yaml_file_pattern
        YAML_REGEXP
      end

      sig { override.returns(Regexp) }
      def container_image_regex
        IMAGE_REGEX
      end

      sig { override.params(escaped_declaration: String).returns(Regexp) }
      def build_old_declaration_regex(escaped_declaration)
        %r{#{IMAGE_REGEX}\s+["']?(docker\.io/)?#{escaped_declaration}["']?(?=\s|$)}
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []
        dependency_files.each do |file|
          next unless requirement_changed?(file, T.must(dependency))

          if file.name.match?(CHART_YAML_REGEXP)
            updated_files << updated_file(
              file: file,
              content: T.must(updated_chart_yaml_content(file))
            )
          elsif file.name.match?(VALUES_YAML_REGEXP)
            updated_files << updated_file(
              file: file,
              content: T.must(updated_values_yaml_content(file))
            )
          end
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig do
        params(content: String, yaml_obj: T::Hash[T.untyped, T.untyped],
               file: Dependabot::DependencyFile).returns(String)
      end
      def update_chart_dependencies(content, yaml_obj, file)
        if update_chart_dependency?(file)
          yaml_obj["dependencies"].each do |dep|
            next unless dep["name"] == T.must(dependency).name

            old_version = dep["version"].to_s
            new_version = T.must(dependency).version

            pattern = /
              (\s+-\sname:\s#{Regexp.escape(T.must(dependency).name)}.*?\n\s+version:\s)
              ["']?#{Regexp.escape(old_version)}["']?
            /mx
            content = content.gsub(pattern) do |match|
              match.gsub(/version: ["']?#{Regexp.escape(old_version)}["']?/, "version: #{new_version}")
            end
          end
        end
        content
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_chart_yaml_content(file)
        content = file.content
        yaml_obj = YAML.safe_load(T.must(content))

        content = update_chart_dependencies(content, yaml_obj, file)

        raise "Expected content to change!" if content == file.content

        content
      end

      sig { params(content: String, path: String, old_tag: String, new_tag: String).returns(String) }
      def update_tag(content, path, old_tag, new_tag)
        indent_pattern = get_indent_pattern(content, path)
        tag_pattern = /#{indent_pattern}tag:\s+["']?#{Regexp.escape(old_tag)}["']?/
        content.gsub(tag_pattern, "#{indent_pattern}tag: #{new_tag}")
      end

      sig { params(content: String, path: String, old_image: String, new_image: String).returns(String) }
      def update_image(content, path, old_image, new_image)
        indent_pattern = get_indent_pattern(content, path)
        image_pattern = /#{indent_pattern}image:\s+["']?#{Regexp.escape(old_image)}["']?/
        content.gsub(image_pattern, "#{indent_pattern}image: #{new_image}")
      end

      sig { params(content: String, path_parts: T::Array[String]).returns(String) }
      def update_tag_in_content(content, path_parts)
        parent_path = T.must(path_parts[0...-1]).join(".")
        old_tag = T.must(dependency).previous_version
        new_tag = T.must(dependency).version
        update_tag(content, parent_path, T.must(old_tag), T.must(new_tag))
      end

      sig { params(content: String, path: String, req: T::Hash[Symbol, T.untyped]).returns(String) }
      def update_image_in_content(content, path, req)
        old_image = build_old_image_string(req)
        new_image = build_new_image_string(req)
        update_image(content, path, old_image, new_image)
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_values_yaml_content(file)
        content = file.content
        req = T.must(dependency).requirements.find { |r| r[:file] == file.name }

        if update_container_image?(file) && req&.dig(:source, :path)
          path = req.dig(:source, :path).to_s
          path_parts = path.split(".")

          content = if path_parts.last == "tag"
                      update_tag_in_content(T.must(content), path_parts)
                    elsif path_parts.last == "image"
                      update_image_in_content(T.must(content), path, req)
                    else
                      content
                    end
        end

        raise "Expected content to change!" if content == file.content

        content
      end

      sig { params(content: String, path: String).returns(String) }
      def get_indent_pattern(content, path)
        path_parts = path.split(".")
        indent = T.let("", T.untyped)

        path_parts.each do |part|
          pattern = /^(#{indent}\s*)#{part}:/
          if content.match(pattern)
            indent = T.must(T.must(content.match(pattern))[1]) + "  " # Add 2 spaces for next level
          end
        end

        indent
      end

      sig { params(requirement: T::Hash[Symbol, T.untyped]).returns(String) }
      def build_old_image_string(requirement)
        old_source = requirement.fetch(:source)
        prefix = old_source[:registry] ? "#{old_source[:registry]}/" : ""
        name = T.must(dependency).name
        tag = T.must(dependency).previous_version
        digest = old_source[:digest] ? "@sha256:#{old_source[:digest]}" : ""

        "#{prefix}#{name}:#{tag}#{digest}"
      end

      sig { params(requirement: T::Hash[Symbol, T.untyped]).returns(String) }
      def build_new_image_string(requirement)
        new_source = requirement.fetch(:source)
        prefix = new_source[:registry] ? "#{new_source[:registry]}/" : ""
        name = T.must(dependency).name
        tag = T.must(dependency).version
        digest = new_source[:digest] ? "@sha256:#{new_source[:digest]}" : ""

        "#{prefix}#{name}:#{tag}#{digest}"
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def update_chart_dependency?(file)
        reqs = T.must(dependency).requirements.select { |r| r[:file] == file.name }
        reqs.any? { |r| r[:metadata]&.dig(:type) == :helm_chart }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def update_container_image?(file)
        reqs = T.must(dependency).requirements.select { |r| r[:file] == file.name }
        reqs.any? { |r| r[:groups]&.include?("image") }
      end
    end
  end
end

Dependabot::FileUpdaters.register("helm", Dependabot::Helm::FileUpdater)
