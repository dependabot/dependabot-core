# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "pathname"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/python/file_parser"
require "dependabot/python/language_version_manager"
require "dependabot/python/name_normaliser"
require "dependabot/python/pip_compile_file_matcher"
require "dependabot/python/pipenv_runner"
require "dependabot/python/shared_file_fetcher"
require "toml-rb"

module Dependabot
  module Python
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      require_relative "dependency_grapher/lockfile_generator"
      require_relative "dependency_grapher/requirements_layers"

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        dependency_files_by_package_manager = T.let(
          {
            PipenvPackageManager::NAME => [pipfile_lock, pipfile],
            PoetryPackageManager::NAME => [committed_poetry_lock, pyproject_toml],
            PipCompilePackageManager::NAME => [pip_compile_lockfile, pip_compile_manifest, pyproject_toml],
            PipPackageManager::NAME => [pip_requirements_file, pyproject_toml, pipfile_lock, pipfile, setup_file,
                                        setup_cfg_file]
          },
          T::Hash[String, T::Array[T.nilable(Dependabot::DependencyFile)]]
        )

        candidates = dependency_files_by_package_manager.fetch(python_package_manager, [])
        relevant_file = candidates.compact.first
        return relevant_file if relevant_file

        # If we do not have any dependencies to report, the absence of a relevant manifest file is tolerable, it
        # means the file fetcher retrieved bystander `txt` files we have filtered out and the correct outcome
        # is a blank snapshot for this path.
        return empty_manifest_file if resolved_dependencies.empty?

        # If dependencies resolved but no owning manifest could be identified, we are in an inconsistent state
        # that we cannot represent.
        raise DependabotError, "No supported dependency file present."
      end

      sig { override.void }
      def prepare!
        # Exclude .txt files that don't look like pip manifests before we parse anything to avoid risk of bystander
        # files in non-pip projects.
        filter_non_manifest_txt_files!

        if poetry_project_without_lockfile?
          # Generating an ephemeral lockfile requires executing `poetry lock`. Strictly speaking, that violates our
          # policy of refusing to run Python tooling when external code execution is disallowed, so fail fast.
          raise Dependabot::UnexpectedExternalCode if file_parser.reject_external_code?

          Dependabot.logger.info("No poetry.lock found, generating ephemeral lockfile for dependency graphing")
          generate_ephemeral_lockfile!
          emit_missing_lockfile_warning! if @ephemeral_lockfile_generated
        end
        super
      end

      # Layering is specific to pip / pip-compile for Python.
      sig { override.returns(T::Array[Dependabot::DependencyGraphers::ManifestGroup]) }
      def manifest_groups
        return super unless supports_layering?

        groups = RequirementsLayers.new(dependency_files: dependency_files).groups
        # If we try to apply grouping, but find there is only one group, we prefer
        # to fallback to the base method (the whole directory parsed as one manifest,
        # which naturally includes any setup.py/setup.cfg/pyproject.toml present).
        return super if groups.length < 2

        groups + non_requirements_manifest_groups
      end

      private

      # When a pip/pip-compile directory is split into requirements layers, any non-requirements manifest
      # sharing that directory (setup.py, setup.cfg, pyproject.toml) would otherwise fall outside every layer
      # group and have its dependencies dropped.
      #
      # We instead emit each as its own self-attributed group so its dependencies are preserved and attributed
      # to the file itself. This matches existing static analysis behaviour.
      #
      # NOTE:
      # This logic is only applied on the pip/pip-compile path, so poetry.lock/Pipfile.lock are absent as they would
      # select the poetry/pipenv path which does not support layering.
      #
      # If a pyproject.toml is present, it is treated as a pip-context manifest.
      sig { returns(T::Array[Dependabot::DependencyGraphers::ManifestGroup]) }
      def non_requirements_manifest_groups
        [setup_file, setup_cfg_file, pyproject_toml].compact.map do |file|
          Dependabot::DependencyGraphers::ManifestGroup.new(primary: file, files: [file])
        end
      end

      # An empty, nameless dependency file used to represent a directory that has no supported manifest and
      # resolves to no dependencies. The submission layer treats a nameless manifest as "nothing to report",
      # producing a valid, empty snapshot for the directory instead of a failure.
      sig { returns(Dependabot::DependencyFile) }
      def empty_manifest_file
        Dependabot::DependencyFile.new(
          name: "",
          content: "",
          directory: file_parser.source&.directory || "/"
        )
      end

      # Non-.txt files (pyproject.toml, setup.py, Pipfile, lockfiles, .in files, etc.) are always retained.
      # A .txt file is kept when its name looks like a pip requirements/dependencies manifest, the pip-compile
      # matcher recognises it as a compiled lockfile, or it is referenced (transitively) via `-r`/`-c` from a
      # retained requirements file. The last case preserves constraint/child files (e.g. `constraints.txt`) that
      # the parser needs on disk to resolve a real manifest, while still dropping bystander `.txt` files.
      sig { void }
      def filter_non_manifest_txt_files!
        keep = txt_files_to_keep

        file_parser.dependency_files.reject! do |file|
          next false unless file.name.end_with?(".txt")

          !keep.include?(file.name)
        end
      end

      # Names of the `.txt` files that must be retained: those that look like manifests or pip-compile lockfiles,
      # plus any `.txt` reachable via `-r`/`-c` references from a retained requirements file (`.in` files are
      # never dropped, so references originating from them are followed too).
      sig { returns(T::Set[String]) }
      def txt_files_to_keep
        files_by_name = dependency_files.to_h { |file| [file.name, file] }

        seeds = dependency_files.select do |file|
          file.name.end_with?(".txt") &&
            (RequirementsLayers.manifest_txt_filename?(file.name) ||
              pip_compile_file_matcher.lockfile_for_pip_compile_file?(file))
        end

        # `.in` files are always retained, so a `.txt` they reference must be kept too.
        roots = seeds + dependency_files.select { |file| file.name.end_with?(".in") }

        reachable_txt_names(roots, files_by_name, Set.new(seeds.map(&:name)))
      end

      # Breadth-first closure over `-r`/`-c` references starting from `roots`, adding every referenced `.txt`
      # file that exists in `files_by_name` to `keep`.
      sig do
        params(
          roots: T::Array[Dependabot::DependencyFile],
          files_by_name: T::Hash[String, Dependabot::DependencyFile],
          keep: T::Set[String]
        ).returns(T::Set[String])
      end
      def reachable_txt_names(roots, files_by_name, keep)
        queue = roots.dup
        until queue.empty?
          file = T.must(queue.shift)
          referenced_txt_names(file).each do |name|
            referenced_file = files_by_name[name]
            next if referenced_file.nil? || keep.include?(name)

            keep << name
            queue << referenced_file
          end
        end

        keep
      end

      # Resolves the `.txt` files referenced from a requirements file via `-r`/`-c`, returning their names
      # relative to the repo (matching the fetched DependencyFile names) so we can retain them. Delegates to
      # RequirementsLayers.referenced_paths so grouping and the bystander filter resolve references identically.
      sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
      def referenced_txt_names(file)
        RequirementsLayers.referenced_paths(file).select { |path| path.end_with?(".txt") }
      end

      sig { returns(T::Boolean) }
      def supports_layering?
        [PipPackageManager::NAME, PipCompilePackageManager::NAME].include?(python_package_manager)
      end

      # Returns the poetry.lock only if it was committed to the repo,
      # not if it was generated ephemerally. This ensures that
      # relevant_dependency_file reports the real manifest (pyproject.toml).
      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def committed_poetry_lock
        return nil if @ephemeral_lockfile_generated

        poetry_lock
      end

      # The file parser only identifies Poetry when poetry.lock is present,
      # so we detect it independently by checking for [tool.poetry] in pyproject.toml.
      # Within the python image, no other package manager uses this section
      # (uv runs in a separate image).
      sig { returns(T::Boolean) }
      def poetry_project_without_lockfile?
        return false if poetry_lock
        return false unless pyproject_toml

        parsed = TomlRB.parse(T.must(pyproject_toml&.content))
        !parsed.dig("tool", "poetry").nil?
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        false
      end

      sig { returns(String) }
      def python_package_manager
        T.must(file_parser.ecosystem).package_manager.name
      end

      sig { void }
      def generate_ephemeral_lockfile!
        generator = LockfileGenerator.new(
          dependency_files: dependency_files,
          credentials: file_parser.credentials
        )

        ephemeral_lockfile = generator.generate
        inject_ephemeral_lockfile(ephemeral_lockfile)
        @ephemeral_lockfile_generated = T.let(true, T.nilable(T::Boolean))

        Dependabot.logger.info(
          "Successfully generated ephemeral #{ephemeral_lockfile.name} for dependency graphing"
        )
      rescue StandardError => e
        errored_fetching_subdependencies!
        @subdependency_error = e
        Dependabot.logger.warn(
          "Failed to generate ephemeral lockfile: #{e.message}. " \
          "Dependency versions may not be resolved."
        )
      end

      sig { params(ephemeral_lockfile: Dependabot::DependencyFile).void }
      def inject_ephemeral_lockfile(ephemeral_lockfile)
        dependency_files << ephemeral_lockfile
      end

      sig { void }
      def emit_missing_lockfile_warning!
        Dependabot.logger.warn(
          "No poetry.lock was found in this repository. " \
          "Dependabot generated a temporary lockfile to determine exact dependency versions.\n\n" \
          "To ensure consistent builds and security scanning, we recommend committing your poetry.lock file. " \
          "Without a committed lockfile, resolved dependency versions may change between scans " \
          "due to new package releases."
        )
      end

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_name_set.include?(child) }
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "pypi"
      end

      # Strip extras (e.g. "[filecache]") from the dependency name for PURLs,
      # since the PURL should reference the base package only.
      sig { override.params(dependency: Dependabot::Dependency).returns(String) }
      def purl_name_for(dependency)
        NameNormaliser.normalise(dependency.name)
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        case python_package_manager
        when PoetryPackageManager::NAME
          poetry_lock ? fetch_poetry_lock_relationships : {}
        when PipenvPackageManager::NAME
          pipfile_lock ? fetch_pipfile_lock_relationships : {}
        else
          {}
        end
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_poetry_lock_relationships
        TomlRB.parse(T.must(poetry_lock).content).fetch("package", []).each_with_object({}) do |pkg, rels|
          next unless pkg.is_a?(Hash) && pkg["name"].is_a?(String)

          parent = NameNormaliser.normalise(pkg["name"])
          deps = pkg["dependencies"]
          deps = {} unless deps.is_a?(Hash)
          children = deps.keys.map { |name| NameNormaliser.normalise(name) }
          rels[parent] = children
        end
      rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
        raise Dependabot::DependencyFileNotParseable, T.must(poetry_lock).name
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_pipfile_lock_relationships
        json_output = pipenv_runner.run_pipenv_graph
        parse_pipenv_graph_output(json_output)
      end

      # Parses the JSON output from `pipenv graph --json`.
      #
      # The format is a flat list where each entry has a "package" object and a "dependencies" array:
      #   [
      #     {
      #       "package": { "package_name": "requests", "installed_version": "2.32.5", ... },
      #       "dependencies": [
      #         { "package_name": "certifi", "installed_version": "2024.2.2", ... },
      #         ...
      #       ]
      #     },
      #     ...
      #   ]
      sig { params(json_output: String).returns(T::Hash[String, T::Array[String]]) }
      def parse_pipenv_graph_output(json_output)
        graph = JSON.parse(json_output)
        return {} unless valid_pipenv_graph_array?(graph)

        graph.each_with_object({}) do |entry, rels|
          parent = pipenv_parent_name(entry)
          next unless parent

          rels[parent] = pipenv_child_names(entry)
        end
      rescue JSON::ParserError
        Dependabot.logger.warn("Unexpected output from 'pipenv graph --json': could not parse as JSON")
        {}
      end

      sig { params(graph: T.untyped).returns(T::Boolean) }
      def valid_pipenv_graph_array?(graph)
        return true if graph.is_a?(Array)

        Dependabot.logger.warn("Unexpected output from 'pipenv graph --json': expected a JSON array")
        false
      end

      sig { params(entry: T.untyped).returns(T.nilable(String)) }
      def pipenv_parent_name(entry)
        return nil unless entry.is_a?(Hash)

        pkg = entry["package"]
        return nil unless pkg.is_a?(Hash)

        package_name = pkg["package_name"]
        return nil unless package_name.is_a?(String)

        NameNormaliser.normalise(package_name)
      end

      sig { params(entry: T.untyped).returns(T::Array[String]) }
      def pipenv_child_names(entry)
        deps = entry.is_a?(Hash) ? entry["dependencies"] : nil
        return [] unless deps.is_a?(Array)

        deps.filter_map do |dep|
          next unless dep.is_a?(Hash)

          package_name = dep["package_name"]
          next unless package_name.is_a?(String)

          NameNormaliser.normalise(package_name)
        end
      end

      sig { returns(T::Set[String]) }
      def dependency_name_set
        @dependency_name_set ||= T.let(
          Set.new(@dependencies.map(&:name)),
          T.nilable(T::Set[String])
        )
      end

      sig { returns(PipenvRunner) }
      def pipenv_runner
        @pipenv_runner ||= T.let(
          PipenvRunner.new(
            dependency: nil,
            lockfile: pipfile_lock,
            language_version_manager: language_version_manager,
            dependency_files: dependency_files
          ),
          T.nilable(PipenvRunner)
        )
      end

      sig { returns(LanguageVersionManager) }
      def language_version_manager
        @language_version_manager ||= T.let(
          LanguageVersionManager.new(
            python_requirement_parser: python_requirement_parser
          ),
          T.nilable(LanguageVersionManager)
        )
      end

      sig { returns(FileParser::PythonRequirementParser) }
      def python_requirement_parser
        @python_requirement_parser ||= T.let(
          FileParser::PythonRequirementParser.new(
            dependency_files: dependency_files
          ),
          T.nilable(FileParser::PythonRequirementParser)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pyproject_toml
        dependency_file("pyproject.toml")
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def poetry_lock
        dependency_file(PoetryPackageManager::LOCKFILE_NAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile
        dependency_file(PipenvPackageManager::MANIFEST_FILENAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pipfile_lock
        dependency_file(PipenvPackageManager::LOCKFILE_FILENAME)
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def setup_file
        dependency_file("setup.py")
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def setup_cfg_file
        dependency_file("setup.cfg")
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      def requirements_in_files
        @requirements_in_files ||= T.let(
          dependency_files.select { |f| f.name.end_with?(".in") },
          T.nilable(T::Array[Dependabot::DependencyFile])
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pip_compile_lockfile
        return @pip_compile_lockfile if defined?(@pip_compile_lockfile)

        @pip_compile_lockfile = T.let(
          dependency_files.find { |f| pip_compile_file_matcher.lockfile_for_pip_compile_file?(f) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pip_compile_manifest
        return @pip_compile_manifest if defined?(@pip_compile_manifest)

        lockfile = pip_compile_lockfile
        @pip_compile_manifest = T.let(
          if lockfile
            pip_compile_file_matcher.manifest_for_pip_compile_lockfile(lockfile)
          else
            requirements_in_files.first
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pip_requirements_file
        return @pip_requirements_file if defined?(@pip_requirements_file)

        @pip_requirements_file = T.let(
          dependency_files.find { |f| f.name == "requirements.txt" } ||
            dependency_files.find { |f| f.name.end_with?(".txt") && RequirementsLayers.manifest_txt_filename?(f.name) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { params(filename: String).returns(T.nilable(Dependabot::DependencyFile)) }
      def dependency_file(filename)
        dependency_files.find { |file| file.name == filename }
      end

      sig { returns(PipCompileFileMatcher) }
      def pip_compile_file_matcher
        @pip_compile_file_matcher ||= T.let(
          PipCompileFileMatcher.new(requirements_in_files),
          T.nilable(PipCompileFileMatcher)
        )
      end
    end
  end
end

Dependabot::DependencyGraphers.register("pip", Dependabot::Python::DependencyGrapher)
