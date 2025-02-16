# typed: strict
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Shared
      class FileUpdater < Dependabot::FileUpdaters::Base
        extend T::Sig

        abstract!

        class NoChangeError < StandardError
          extend T::Sig

          sig { params(message: String, error_context: T::Hash[Symbol, T.untyped]).void }
          def initialize(message:, error_context:)
            super(message)
            @error_context = error_context
          end

          sig { returns(T::Hash[Symbol, T.untyped]) }
          def sentry_context
            { extra: @error_context }
          end
        end

        sig { override.returns(T::Array[DependencyFile]) }
        def updated_dependency_files
          updated_files = T.let([], T::Array[DependencyFile])

          updated_files += updated_manifest_files
          updated_files += updated_lockfiles

          if updated_files.none?
            raise NoChangeError.new(
              message: "No files were updated!",
              error_context: error_context(updated_files: updated_files)
            )
          end

          sorted_updated_files = updated_files.sort_by(&:name)
          if sorted_updated_files == filtered_dependency_files.sort_by(&:name)
            raise NoChangeError.new(
              message: "Updated files are unchanged!",
              error_context: error_context(updated_files: updated_files)
            )
          end

          vendor_updated_files(updated_files)
        end

        private

        sig do
          params(updated_files: T::Array[Dependabot::DependencyFile]).returns(T::Array[Dependabot::DependencyFile])
        end
        def vendor_updated_files(updated_files)
          base_dir = T.must(updated_files.first).directory
          T.unsafe(vendor_updater).updated_vendor_cache_files(base_directory: base_dir).each do |file|
            updated_files << file
          end
          install_state_updater.updated_files(base_directory: base_dir).each do |file|
            updated_files << file
          end

          updated_files
        end

        # Dynamically fetch the vendor cache folder from yarn
        sig { returns(String) }
        def vendor_cache_dir
          @vendor_cache_dir ||= T.let(
            "./.yarn/cache",
            T.nilable(String)
          )
        end

        sig { returns(String) }
        def install_state_path
          @install_state_path ||= T.let(
            "./.yarn/install-state.gz",
            T.nilable(String)
          )
        end

        sig { returns(Dependabot::FileUpdaters::VendorUpdater) }
        def vendor_updater
          Dependabot::FileUpdaters::VendorUpdater.new(
            repo_contents_path: repo_contents_path,
            vendor_dir: vendor_cache_dir
          )
        end

        sig { returns(Dependabot::FileUpdaters::ArtifactUpdater) }
        def install_state_updater
          Dependabot::FileUpdaters::ArtifactUpdater.new(
            repo_contents_path: repo_contents_path,
            target_directory: install_state_path
          )
        end

        sig { returns(Dependabot::FileUpdaters::ArtifactUpdater) }
        def pnp_updater
          Dependabot::FileUpdaters::ArtifactUpdater.new(
            repo_contents_path: repo_contents_path,
            target_directory: "./"
          )
        end

        sig { returns(T::Array[DependencyFile]) }
        def filtered_dependency_files
          @filtered_dependency_files ||= T.let(
            if dependencies.any?(&:top_level?)
              Shared::DependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: dependencies,
                lockfile_parser_class: lockfile_parser_class
              ).files_requiring_update
            else
              Shared::SubDependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: dependencies
              ).files_requiring_update
            end, T.nilable(T::Array[DependencyFile])
          )
        end

        sig { abstract.returns(T.class_of(FileParser::LockfileParser)) }
        def lockfile_parser_class; end

        sig { override.void }
        def check_required_files
          raise DependencyFileNotFound.new(nil, "package.json not found.") unless get_original_file("package.json")
        end

        sig { params(updated_files: T::Array[DependencyFile]).returns(T::Hash[Symbol, T.untyped]) }
        def error_context(updated_files:)
          {
            dependencies: dependencies.map(&:to_h),
            updated_files: updated_files.map(&:name),
            dependency_files: dependency_files.map(&:name)
          }
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def package_files
          @package_files ||= T.let(
            filtered_dependency_files.select do |f|
              f.name.end_with?("package.json")
            end, T.nilable(T::Array[DependencyFile])
          )
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def updated_manifest_files
          package_files.filter_map do |file|
            updated_content = updated_package_json_content(file)
            next if updated_content == file.content

            updated_file(file: file, content: T.must(updated_content))
          end
        end

        sig { abstract.returns(T::Array[Dependabot::DependencyFile]) }
        def updated_lockfiles; end

        sig { params(file: Dependabot::DependencyFile).returns(T.nilable(String)) }
        def updated_package_json_content(file)
          @updated_package_json_content ||= T.let({}, T.nilable(T::Hash[String, T.nilable(String)]))
          @updated_package_json_content[file.name] ||=
            PackageJsonUpdater.new(
              package_json: file,
              dependencies: dependencies
            ).updated_package_json.content
        end
      end
    end
  end
end
