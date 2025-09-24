# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/opentofu/file_selector"
require "dependabot/file_filtering"

module Dependabot
  module Opentofu
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig
      extend T::Helpers

      include FileFilter

      # https://opentofu.org/docs/language/modules/sources/#local-paths
      LOCAL_PATH_SOURCE = %r{source\s*=\s*['"](?<path>..?\/[^'"]+)}

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| f.end_with?(".tf", ".tofu", ".hcl") }
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a OpenTofu configuration file."
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        unless allow_beta_ecosystems?
          raise Dependabot::DependencyFileNotFound.new(
            nil,
            "OpenTofu support is currently in beta. Set ALLOW_BETA_ECOSYSTEMS=true to enable it."
          )
        end
        fetched_files = []
        fetched_files += opentofu_files
        fetched_files += terragrunt_files
        fetched_files += local_path_module_files(opentofu_files)
        fetched_files += [lockfile] if lockfile

        filtered_files = fetched_files.compact.reject do |file|
          Dependabot::FileFiltering.should_exclude_path?(file.name, "file from final collection", @exclude_paths)
        end

        filtered_files
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def opentofu_files
        @opentofu_files ||= T.let(
          repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && f.name.end_with?(".tf", ".tofu") }
          .map { |f| fetch_file_from_host(f.name) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def terragrunt_files
        @terragrunt_files ||= T.let(
          repo_contents(raise_errors: false)
          .select { |f| f.type == "file" && terragrunt_file?(f.name) }
          .map { |f| fetch_file_from_host(f.name) },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig do
        params(
          files: T::Array[Dependabot::DependencyFile],
          dir: String
        )
          .returns(T::Array[Dependabot::DependencyFile])
      end
      def local_path_module_files(files, dir: ".")
        opentofu_files = T.let([], T::Array[Dependabot::DependencyFile])

        files.each do |file|
          opentofu_file_local_module_details(file).each do |path|
            base_path = Pathname.new(File.join(dir, path)).cleanpath.to_path

            # Skip excluded local module paths
            if Dependabot::FileFiltering.should_exclude_path?(base_path, "local path module directory", @exclude_paths)
              next
            end

            nested_opentofu_files =
              repo_contents(dir: base_path)
              .select { |f| f.type == "file" && f.name.end_with?(".tf", ".tofu") }
              .map { |f| fetch_file_from_host(File.join(base_path, f.name)) }
            opentofu_files += nested_opentofu_files
            opentofu_files += local_path_module_files(nested_opentofu_files, dir: path)
          end
        end

        # NOTE: The `support_file` attribute is not used but we set this to
        # match what we do in other ecosystems
        opentofu_files.tap { |fs| fs.each { |f| f.support_file = true } }
      end

      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def opentofu_file_local_module_details(file)
        return [] unless file.name.end_with?(".tf", ".tofu")
        return [] unless file.content&.match?(LOCAL_PATH_SOURCE)

        T.must(file.content).scan(LOCAL_PATH_SOURCE).flatten.map do |path|
          Pathname.new(path).cleanpath.to_path
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          fetch_file_if_present(".terraform.lock.hcl"),
          T.nilable(Dependabot::DependencyFile)
        )
      end
    end
  end
end

Dependabot::FileFetchers
  .register("opentofu", Dependabot::Opentofu::FileFetcher)
