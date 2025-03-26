# typed: strict
# frozen_string_literal: true

require "dependabot/shared/shared_file_updater"
require "dependabot/helm/file_updater/lock_file_generator"
require "dependabot/helm/file_updater/image_updater"
require "dependabot/helm/file_updater/chart_updater"
require "yaml"

module Dependabot
  module Helm
    class FileUpdater < Dependabot::Shared::SharedFileUpdater
      extend T::Sig
      extend T::Helpers

      CHART_YAML_REGEXP = /Chart\.ya?ml/i
      CHART_LOCK_REGEXP = /Chart\.lock/i
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
            updated_content = chart_updater.updated_chart_yaml_content(file)
            updated_files << updated_file(
              file: file,
              content: T.must(updated_content)
            )

            updated_files.concat(update_chart_locks(T.must(updated_content))) if chart_locks
          elsif file.name.match?(VALUES_YAML_REGEXP)
            updated_files << updated_file(
              file: file,
              content: T.must(image_updater.updated_values_yaml_content(file.name))
            )
          end
        end

        updated_files.reject! { |f| dependency_files.include?(f) }
        raise "No files changed!" if updated_files.none?

        updated_files
      end

      private

      sig { params(updated_content: String).returns(T::Array[Dependabot::DependencyFile]) }
      def update_chart_locks(updated_content)
        chart_locks.map do |chart_lock|
          updated_file(
            file: chart_lock,
            content: updated_chart_lock_content(chart_lock, updated_content)
          )
        end
      end

      sig { returns(LockFileGenerator) }
      def lockfile_updater
        @lockfile_updater ||= T.let(LockFileGenerator.new(
                                      dependencies: dependencies,
                                      dependency_files: dependency_files,
                                      repo_contents_path: T.must(repo_contents_path),
                                      credentials: credentials
                                    ), T.nilable(Dependabot::Helm::FileUpdater::LockFileGenerator))
      end

      sig { returns(ImageUpdater) }
      def image_updater
        @image_updater ||= T.let(ImageUpdater.new(dependency: T.must(dependency), dependency_files: dependency_files),
                                 T.nilable(Dependabot::Helm::FileUpdater::ImageUpdater))
      end

      sig { returns(ChartUpdater) }
      def chart_updater
        @chart_updater ||= T.let(ChartUpdater.new(dependency: T.must(dependency)),
                                 T.nilable(Dependabot::Helm::FileUpdater::ChartUpdater))
      end

      sig { params(chart_lock: Dependabot::DependencyFile, updated_content: String).returns(String) }
      def updated_chart_lock_content(chart_lock, updated_content)
        @updated_chart_lock_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
        @updated_chart_lock_content[chart_lock.name] ||=
          lockfile_updater.updated_chart_lock(chart_lock, updated_content)
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def chart_locks
        @chart_locks ||= T.let(
          dependency_files
            .select { |f| f.name.match(CHART_LOCK_REGEXP) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end
    end
  end
end

Dependabot::FileUpdaters.register("helm", Dependabot::Helm::FileUpdater)
