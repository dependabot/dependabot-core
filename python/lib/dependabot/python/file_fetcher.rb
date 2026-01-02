# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"

require "dependabot/file_fetchers"
require "dependabot/python/shared_file_fetcher"
require "dependabot/python/pip_compile_file_matcher"
require "dependabot/python/file_parser/pyproject_files_parser"
require "dependabot/errors"

module Dependabot
  module Python
    class FileFetcher < Dependabot::Python::SharedFileFetcher
      extend T::Sig

      ECOSYSTEM_SPECIFIC_FILES = T.let(%w(Pipfile setup.py setup.cfg).freeze, T::Array[String])

      sig { override.returns(T::Array[String]) }
      def self.ecosystem_specific_required_files
        ECOSYSTEM_SPECIFIC_FILES
      end

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a requirements.txt, setup.py, setup.cfg, pyproject.toml, " \
          "or a Pipfile."
      end

      private

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def ecosystem_specific_files
        files = []
        files += pipenv_files
        files << setup_file if setup_file
        files << setup_cfg_file if setup_cfg_file
        files << pip_conf if pip_conf
        files
      end

      sig { override.returns(T::Array[Dependabot::DependencyFile]) }
      def pyproject_files
        [pyproject, poetry_lock, pdm_lock].compact
      end

      sig { override.returns(T::Array[T::Hash[Symbol, String]]) }
      def path_dependencies
        requirement_txt_path_dependencies +
          requirement_in_path_dependencies +
          pipfile_path_dependencies
      end

      sig { override.returns(T::Array[String]) }
      def additional_path_dependencies
        poetry_path_dependencies
      end

      sig { override.params(file: Dependabot::DependencyFile).returns(T::Boolean) }
      def lockfile_for_compile_file?(file)
        pip_compile_file_matcher.lockfile_for_pip_compile_file?(file)
      end

      sig { override.params(path: String).returns(T::Array[Dependabot::DependencyFile]) }
      def fetch_project_file(path)
        project_files = []

        path = clean_path(File.join(path, "setup.py")) unless sdist_or_wheel?(path)

        return [] if path == "setup.py" && setup_file

        project_files <<
          begin
            fetch_file_from_host(
              path,
              fetch_submodules: true
            ).tap { |f| f.support_file = true }
          rescue Dependabot::DependencyFileNotFound
            # For projects with pyproject.toml attempt to fetch a pyproject.toml
            # at the given path instead of a setup.py.
            fetch_file_from_host(
              path.gsub("setup.py", "pyproject.toml"),
              fetch_submodules: true
            ).tap { |f| f.support_file = true }
          end

        return project_files unless path.end_with?(".py")

        project_files + cfg_files_for_setup_py(path)
      end

      # Python-specific methods

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def pipenv_files
        [pipfile, pipfile_lock].compact
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def setup_file
        @setup_file ||= T.let(
          fetch_file_if_present("setup.py"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def setup_cfg_file
        @setup_cfg_file ||= T.let(
          fetch_file_if_present("setup.cfg"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pip_conf
        @pip_conf ||= T.let(
          fetch_support_file("pip.conf"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile
        @pipfile ||= T.let(
          fetch_file_if_present("Pipfile"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile_lock
        @pipfile_lock ||= T.let(
          fetch_file_if_present("Pipfile.lock"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def poetry_lock
        @poetry_lock ||= T.let(
          fetch_file_if_present("poetry.lock"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pdm_lock
        @pdm_lock ||= T.let(
          fetch_file_if_present("pdm.lock"),
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_pipfile
        raise "No Pipfile" unless pipfile

        @parsed_pipfile ||= T.let(
          TomlRB.parse(T.must(pipfile).content),
          T.nilable(T::Hash[String, T.untyped])
        )
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, T.must(pipfile).path
      end

      sig { params(path: String).returns(T::Array[Dependabot::DependencyFile]) }
      def cfg_files_for_setup_py(path)
        cfg_path = path.gsub(/\.py$/, ".cfg")

        begin
          [
            fetch_file_from_host(cfg_path, fetch_submodules: true)
              .tap { |f| f.support_file = true }
          ]
        rescue Dependabot::DependencyFileNotFound
          # Ignore lack of a setup.cfg
          []
        end
      end

      sig { returns(T::Array[T::Hash[Symbol, String]]) }
      def pipfile_path_dependencies
        return [] unless pipfile

        deps = []
        DEPENDENCY_TYPES.each do |dep_type|
          next unless parsed_pipfile[dep_type]

          parsed_pipfile[dep_type].each do |_, req|
            next unless req.is_a?(Hash) && req["path"]

            deps << { name: req["path"], path: req["path"], file: T.must(pipfile).name }
          end
        end

        deps
      end

      sig { returns(T::Array[String]) }
      def poetry_path_dependencies
        return [] unless pyproject

        paths = []
        Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |dep_type|
          next unless parsed_pyproject.dig("tool", "poetry", dep_type)

          parsed_pyproject.dig("tool", "poetry", dep_type).each do |_, req|
            next unless req.is_a?(Hash) && req["path"]

            paths << req["path"]
          end
        end

        paths
      end

      sig { returns(Dependabot::Python::PipCompileFileMatcher) }
      def pip_compile_file_matcher
        @pip_compile_file_matcher ||= T.let(
          PipCompileFileMatcher.new(requirements_in_files),
          T.nilable(Dependabot::Python::PipCompileFileMatcher)
        )
      end
    end
  end
end

Dependabot::FileFetchers.register("pip", Dependabot::Python::FileFetcher)
