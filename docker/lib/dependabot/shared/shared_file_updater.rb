# typed: strict
# frozen_string_literal: true

require "dependabot/file_updaters"
require "dependabot/file_updaters/base"
require "dependabot/errors"
require "sorbet-runtime"
require "dependabot/shared/utils/helpers"

module Dependabot
  module Shared
    class SharedFileUpdater < Dependabot::FileUpdaters::Base
      extend T::Sig
      extend T::Helpers

      abstract!

      FROM_REGEX = /FROM(\s+--platform\=\S+)?/i

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def updated_dependency_files
        updated_files = []
        dependency_files.each do |file|
          next unless requirement_changed?(file, T.must(dependency))

          updated_files << if file.name.match?(T.must(yaml_file_pattern))
                             updated_file(
                               file: file,
                               content: T.must(updated_yaml_content(file))
                             )
                           else
                             updated_file(
                               file: file,
                               content: T.must(updated_dockerfile_content(file))
                             )
                           end
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      sig { abstract.returns(T.nilable(Regexp)) }
      def yaml_file_pattern; end

      sig { abstract.returns(T.nilable(Regexp)) }
      def container_image_regex; end

      private

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_dockerfile_content(file)
        old_sources = previous_sources(file)
        new_sources = sources(file)

        updated_content = T.let(file.content, T.untyped)

        T.must(old_sources).zip(new_sources).each do |old_source, new_source|
          updated_content = update_digest_and_tag(updated_content, old_source, T.must(new_source))
        end

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      sig do
        params(previous_content: String, old_source: T::Hash[Symbol, T.nilable(String)],
               new_source: T::Hash[Symbol, T.nilable(String)]).returns(String)
      end
      def update_digest_and_tag(previous_content, old_source, new_source) # rubocop:disable Metrics/PerceivedComplexity
        old_digest = old_source[:digest]
        new_digest = new_source[:digest]

        old_tag = old_source[:tag]
        new_tag = new_source[:tag]

        old_declaration =
          if private_registry_url(old_source)
            "#{private_registry_url(old_source)}/"
          else
            ""
          end
        old_declaration += T.must(dependency).name
        old_declaration +=
          if specified_with_tag?(old_source)
            ":#{old_tag}"
          else
            ""
          end
        old_declaration +=
          if specified_with_digest?(old_source)
            "@#{old_digest}"
          else
            ""
          end

        escaped_declaration = Regexp.escape(old_declaration)

        old_declaration_regex = build_old_declaration_regex(escaped_declaration)

        previous_content.gsub(old_declaration_regex) do |old_dec|
          old_digest = old_digest.sub("sha256:", "") if old_digest&.start_with?("sha256:")
          new_digest = new_digest.sub("sha256:", "") if new_digest&.start_with?("sha256:")

          old_dec
            .gsub("@sha256:#{old_digest}", "@sha256:#{new_digest}")
            .gsub("@#{old_digest}", "@#{new_digest}")
            .gsub(":#{old_tag}", ":#{new_tag}")
        end
      end

      sig { params(escaped_declaration: String).returns(Regexp) }
      def build_old_declaration_regex(escaped_declaration)
        %r{^#{FROM_REGEX}\s+(docker\.io/)?#{escaped_declaration}(?=\s|$)}
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
      def updated_yaml_content(file)
        updated_content = file.content
        updated_content = update_helm(file, updated_content) if Shared::Utils.likely_helm_chart?(file)
        updated_content = update_image(file, updated_content)

        raise "Expected content to change!" if updated_content == file.content

        updated_content
      end

      sig { params(file: Dependabot::DependencyFile, content: T.nilable(String)).returns(T.nilable(String)) }
      def update_helm(file, content)
        old_tags = old_helm_tags(file)
        return if old_tags.empty?

        modified_content = content

        old_tags.each do |old_tag|
          old_tag_regex = /^\s*(?:-\s)?(?:tag|version):\s+["']?#{old_tag}["']?(?=\s|$)/
          modified_content = modified_content&.gsub(old_tag_regex) do |old_img_tag|
            old_img_tag.gsub(old_tag.to_s, new_helm_tag(file).to_s)
          end
        end
        modified_content
      end

      sig { params(file: Dependabot::DependencyFile, content: T.nilable(String)).returns(T.nilable(String)) }
      def update_image(file, content)
        old_images = old_yaml_images(file)
        return if old_images.empty?

        modified_content = content

        old_images.each do |old_image|
          old_image_regex = /^\s*(?:-\s)?image:\s+#{old_image}(?=\s|$)/
          modified_content = modified_content&.gsub(old_image_regex) do |old_img|
            old_img.gsub(old_image.to_s, new_yaml_image(file).to_s)
          end
        end
        modified_content
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def new_yaml_image(file)
        element = T.must(dependency).requirements.find { |r| r[:file] == file.name }
        prefix = element&.dig(:source, :registry) ? "#{element.fetch(:source)[:registry]}/" : ""
        digest = element&.dig(:source, :digest) ? "@#{element.fetch(:source)[:digest]}" : ""
        tag = element&.dig(:source, :tag) ? ":#{element.fetch(:source)[:tag]}" : ""
        "#{prefix}#{T.must(dependency).name}#{tag}#{digest}"
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def old_yaml_images(file)
        T.must(previous_requirements(file)).map do |r|
          prefix = r.fetch(:source)[:registry] ? "#{r.fetch(:source)[:registry]}/" : ""
          digest = r.fetch(:source)[:digest] ? "@#{r.fetch(:source)[:digest]}" : ""
          tag = r.fetch(:source)[:tag] ? ":#{r.fetch(:source)[:tag]}" : ""
          "#{prefix}#{T.must(dependency).name}#{tag}#{digest}"
        end
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def old_helm_tags(file)
        T.must(previous_requirements(file)).map do |r|
          tag = r.fetch(:source)[:tag] || ""
          digest = r.fetch(:source)[:digest] ? "@#{r.fetch(:source)[:digest]}" : ""
          "#{tag}#{digest}"
        end
      end

      sig { params(file: Dependabot::DependencyFile).returns(String) }
      def new_helm_tag(file)
        element = T.must(dependency).requirements.find { |r| r[:file] == file.name }
        tag = T.must(element).dig(:source, :tag) || ""
        digest = T.must(element).dig(:source, :digest) ? "@#{T.must(element).dig(:source, :digest)}" : ""
        "#{tag}#{digest}"
      end

      protected

      sig { params(file: Dependabot::DependencyFile, dependency: Dependabot::Dependency).returns(T::Boolean) }
      def requirement_changed?(file, dependency)
        changed_requirements =
          dependency.requirements - T.must(dependency.previous_requirements)

        changed_requirements.any? { |f| f[:file] == file.name }
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(T::Boolean) }
      def specified_with_tag?(source)
        !source[:tag].nil?
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(T::Boolean) }
      def specified_with_digest?(source)
        !source[:digest].nil?
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
      def requirements(file)
        T.must(dependency).requirements
         .select { |r| r[:file] == file.name }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(T::Array[T::Hash[Symbol, T.untyped]])) }
      def previous_requirements(file)
        T.must(dependency).previous_requirements
         &.select { |r| r[:file] == file.name }
      end

      sig { params(source: T::Hash[Symbol, T.nilable(String)]).returns(T.nilable(String)) }
      def private_registry_url(source)
        source[:registry]
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
      def sources(file)
        requirements(file).map { |r| r.fetch(:source) }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T.nilable(T::Array[T::Hash[Symbol, T.nilable(String)]])) }
      def previous_sources(file)
        previous_requirements(file)&.map { |r| r.fetch(:source) }
      end

      sig { returns(T.nilable(Dependabot::Dependency)) }
      def dependency
        # Files will only ever be updating a single dependency
        dependencies.first
      end

      sig { override.void }
      def check_required_files
        return if dependency_files.any?

        raise "No #{file_type}!"
      end

      private

      sig { abstract.returns(String) }
      def file_type; end
    end
  end
end
