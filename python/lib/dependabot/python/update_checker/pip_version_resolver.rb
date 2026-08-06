# typed: strong
# frozen_string_literal: true

require "json"
require "fileutils"
require "pathname"
require "shellwords"
require "toml-rb"
require "sorbet-runtime"
require "excon"
require "dependabot/registry_client"
require "dependabot/shared_helpers"
require "dependabot/python/authed_url_builder"
require "dependabot/python/file_updater/requirement_replacer"
require "dependabot/python/language_version_manager"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/update_checker"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/python/file_parser/python_requirement_parser"

module Dependabot
  module Python
    class UpdateChecker
      # This resolver intentionally co-locates resolution, marker handling, and
      # constraints matching to keep compatibility decisions in one place.
      # rubocop:disable Metrics/ClassLength
      class PipVersionResolver
        extend T::Sig

        PIP_REPORT_FILENAME = "dependabot-pip-report.json"
        RESOLUTION_ERROR_PATTERN = /ResolutionImpossible|No matching distribution found/
        LOWER_BOUND_OPERATORS = %w(> >= ~>).freeze
        PIP_REQUIREMENT_FILE_EXTENSIONS = %w(.txt .in).freeze
        HASH_OPTION_PATTERN = /(?:[ \t]*\\[ \t]*\r?\n[ \t]*|[ \t]+)--hash=[^\s\\]+/
        REQUIRE_HASHES_PATTERN = /^\s*--require-hashes(?:\s+#.*)?\r?\n?/
        PIP_FILE_REFERENCE_PATTERN =
          /^\s*(?:-r|--requirement|-c|--constraint)(?:\s+|=)
            (?:"(?<double>[^"]+)"|'(?<single>[^']+)'|(?<plain>[^\s'"]+))/x
        QUOTED_PIP_FILE_REFERENCE_PATTERN =
          /^\s*(?:-r|--requirement|-c|--constraint)(?:\s+|=)["']/
        LowerBound = T.type_alias { [String, Gem::Version] }
        PipResolution = T.type_alias do
          [Dependabot::DependencyFile, T::Array[Dependabot::DependencyRequirement]]
        end

        require_relative "pip_version_resolver/marker_evaluator"

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            security_advisories: T::Array[Dependabot::SecurityAdvisory],
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions),
            raise_on_ignored: T::Boolean
          ).void
        end
        def initialize(
          dependency:,
          dependency_files:,
          credentials:,
          ignored_versions:,
          security_advisories:,
          update_cooldown: nil,
          raise_on_ignored: false
        )
          @dependency = dependency
          @dependency_files = dependency_files
          @credentials = credentials
          @ignored_versions = ignored_versions
          @security_advisories = security_advisories
          @update_cooldown = update_cooldown
          @raise_on_ignored = raise_on_ignored
          @latest_version_finder = T.let(nil, T.nilable(LatestVersionFinder))
          @python_requirement_parser = T.let(nil, T.nilable(FileParser::PythonRequirementParser))
          @language_version_manager = T.let(nil, T.nilable(LanguageVersionManager))
          @marker_evaluator = T.let(nil, T.nilable(MarkerEvaluator))
          @registry_json_urls = T.let(nil, T.nilable(T::Array[String]))
          @transitive_requirements_cache = T.let({}, T::Hash[String, T::Array[String]])
          @transitive_requirement_available_cache = T.let({}, T::Hash[String, T::Boolean])
          @constraints_files = T.let(nil, T.nilable(T::Array[String]))
          @constraints_file_basenames = T.let(nil, T.nilable(T::Array[String]))
          @requirement_file_directories = T.let(nil, T.nilable(T::Array[String]))
          @pyproject_content_cache = T.let({}, T::Hash[String, T::Hash[String, Object]])
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version
          eligible_versions = latest_version_finder.eligible_versions(
            language_version: language_version_manager.python_version
          )
          policy_candidate = eligible_versions.max
          return if policy_candidate.nil?

          candidate = pip_resolvable_version(
            policy_candidate: policy_candidate,
            requirement_string: resolver_requirement(policy_candidate, eligible_versions)
          )
          return unless candidate && eligible_versions.include?(candidate)
          return candidate if compatible_with_pinned_pyproject_dependencies?(candidate)

          nil
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version_with_no_unlock
          latest_version_finder
            .latest_version_with_no_unlock(language_version: language_version_manager.python_version)
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def lowest_resolvable_security_fix_version
          candidate = latest_version_finder
                      .lowest_security_fix_version(language_version: language_version_manager.python_version)
          return candidate if candidate.nil?

          resolved_candidate = pip_resolvable_version(
            policy_candidate: candidate,
            requirement_string: "==#{candidate}"
          )
          return unless resolved_candidate == candidate
          return candidate if compatible_with_pinned_pyproject_dependencies?(candidate)

          nil
        end

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(T::Array[Dependabot::SecurityAdvisory]) }
        attr_reader :security_advisories

        sig { returns(LatestVersionFinder) }
        def latest_version_finder
          @latest_version_finder ||= LatestVersionFinder.new(
            dependency: dependency,
            dependency_files: dependency_files,
            credentials: credentials,
            ignored_versions: ignored_versions,
            raise_on_ignored: @raise_on_ignored,
            cooldown_options: @update_cooldown,
            security_advisories: security_advisories
          )
          @latest_version_finder
        end

        sig { returns(FileParser::PythonRequirementParser) }
        def python_requirement_parser
          @python_requirement_parser ||=
            FileParser::PythonRequirementParser.new(
              dependency_files: dependency_files
            )
        end

        sig { returns(LanguageVersionManager) }
        def language_version_manager
          @language_version_manager ||=
            LanguageVersionManager.new(
              python_requirement_parser: python_requirement_parser
            )
        end

        sig { returns(MarkerEvaluator) }
        def marker_evaluator
          @marker_evaluator ||= MarkerEvaluator.new
        end

        sig do
          params(
            policy_candidate: Dependabot::Version,
            requirement_string: String
          ).returns(T.nilable(Dependabot::Version))
        end
        def pip_resolvable_version(policy_candidate:, requirement_string:)
          resolution = pip_resolution
          return policy_candidate unless resolution

          root_file, requirements = resolution

          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_dependency_files(requirements: requirements, requirement_string: requirement_string)
              language_version_manager.install_required_python
              SharedHelpers.run_shell_command(
                pip_resolver_command(root_file, allow_prereleases: policy_candidate.prerelease?),
                allow_unsafe_shell_command: true,
                env: pip_environment,
                fingerprint: pip_resolver_fingerprint,
                stderr_to_stdout: true
              )

              pip_report_version
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          return nil if e.message.match?(RESOLUTION_ERROR_PATTERN)

          raise
        end

        sig { returns(T.nilable(LowerBound)) }
        def resolver_lower_bound
          current_version = dependency.numeric_version
          return [">", current_version] if current_version

          lower_bounds = dependency.requirements.filter_map { |requirement| lower_bound_for(requirement) }
          lower_bounds.max_by { |_, version| version }
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(LowerBound)) }
        def lower_bound_for(requirement)
          requirement_string = requirement.requirement_string
          return unless requirement_string

          parsed_requirement = Python::Requirement.new(requirement_string)
          lower_bounds = parsed_requirement.requirements.filter_map do |operator, version|
            [operator, version] if LOWER_BOUND_OPERATORS.include?(operator)
          end
          operator, version = lower_bounds.max_by { |_, bound_version| bound_version }
          return unless operator && version

          [operator == ">" ? ">" : ">=", version]
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig do
          params(
            policy_candidate: Dependabot::Version,
            eligible_versions: T::Array[Dependabot::Version]
          ).returns(String)
        end
        def resolver_requirement(policy_candidate, eligible_versions)
          requirements = ["<=#{policy_candidate}"]
          lower_bound = resolver_lower_bound
          requirements.unshift("#{lower_bound[0]}#{lower_bound[1]}") if lower_bound
          requirements.concat(excluded_version_requirements(policy_candidate, eligible_versions))
          requirements.join(",")
        end

        sig do
          params(
            policy_candidate: Dependabot::Version,
            eligible_versions: T::Array[Dependabot::Version]
          ).returns(T::Array[String])
        end
        def excluded_version_requirements(policy_candidate, eligible_versions)
          lower_bound = resolver_lower_bound
          excluded_versions = latest_version_finder.resolver_excluded_versions

          excluded_versions.filter_map do |version|
            next unless version_within_resolver_bounds?(version, policy_candidate, lower_bound)
            next if eligible_versions.include?(version)

            "!=#{version}"
          end
        end

        sig do
          params(
            version: Dependabot::Version,
            policy_candidate: Dependabot::Version,
            lower_bound: T.nilable(LowerBound)
          ).returns(T::Boolean)
        end
        def version_within_resolver_bounds?(version, policy_candidate, lower_bound)
          return false if version > policy_candidate
          return true unless lower_bound

          operator, bound_version = lower_bound
          version > bound_version || (operator != ">" && version == bound_version)
        end

        sig { returns(T.nilable(PipResolution)) }
        def pip_resolution
          requirements = dependency.requirements
          return if requirements.empty?
          return unless requirements.all? { |requirement| pip_compatible_requirement?(requirement) }

          declaration_files = requirements.filter_map do |requirement|
            file = dependency_files.find { |dependency_file| dependency_file.name == requirement.file }
            file if pip_compatible_requirement_file?(file, requirement)
          end
          return unless declaration_files.length == requirements.length

          root_file = pip_resolution_root(declaration_files.map(&:name).uniq)
          return unless root_file

          [root_file, requirements]
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T::Boolean) }
        def pip_compatible_requirement?(requirement)
          requirement.file&.end_with?(".txt") == true &&
            requirement.source.nil? &&
            !requirement.requirement_string.nil?
        end

        sig do
          params(
            file: T.nilable(Dependabot::DependencyFile),
            requirement: Dependabot::DependencyRequirement
          ).returns(T::Boolean)
        end
        def pip_compatible_requirement_file?(file, requirement)
          return false unless file&.content

          content = T.must(file.content)
          return false if content.match?(/^\s*(?:-r|--requirement|-c|--constraint)(?:\s+|=)["']/)

          requirement_declaration_present?(file, requirement)
        end

        sig { params(declaration_file_names: T::Array[String]).returns(T.nilable(Dependabot::DependencyFile)) }
        def pip_resolution_root(declaration_file_names)
          requirement_files = dependency_files.select do |file|
            file.content && file.name.end_with?(*PIP_REQUIREMENT_FILE_EXTENSIONS)
          end
          files_by_name = requirement_files.to_h { |file| [file.name, file] }
          reachable_files = requirement_files.to_h do |file|
            [file.name, reachable_requirement_file_names(file, requirement_files)]
          end
          ancestors = reachable_files.filter_map do |file_name, reachable_file_names|
            file_name if reachable_file_names.intersect?(declaration_file_names)
          end

          requirement_files.find do |file|
            pip_resolution_root_candidate?(file, T.must(reachable_files[file.name]), ancestors, files_by_name)
          end
        end

        sig do
          params(
            file: Dependabot::DependencyFile,
            reachable_file_names: T::Array[String],
            ancestors: T::Array[String],
            files_by_name: T::Hash[String, Dependabot::DependencyFile]
          ).returns(T::Boolean)
        end
        def pip_resolution_root_candidate?(file, reachable_file_names, ancestors, files_by_name)
          return false unless file.name.end_with?(".txt") && (ancestors - reachable_file_names).empty?

          reachable_file_names.none? do |name|
            T.must(T.must(files_by_name[name]).content).match?(QUOTED_PIP_FILE_REFERENCE_PATTERN)
          end
        end

        sig do
          params(
            root_file: Dependabot::DependencyFile,
            requirement_files: T::Array[Dependabot::DependencyFile]
          ).returns(T::Array[String])
        end
        def reachable_requirement_file_names(root_file, requirement_files)
          files_by_name = requirement_files.to_h { |file| [file.name, file] }
          reachable = T.let([], T::Array[String])
          pending = T.let([root_file], T::Array[Dependabot::DependencyFile])

          until pending.empty?
            file = T.must(pending.shift)
            next if reachable.include?(file.name)

            reachable << file.name
            referenced_requirement_file_names(file).each do |name|
              referenced_file = files_by_name[name]
              pending << referenced_file if referenced_file
            end
          end

          reachable
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
        def referenced_requirement_file_names(file)
          current_directory = File.dirname(file.name)
          T.must(file.content).each_line.filter_map do |line|
            match = line.match(PIP_FILE_REFERENCE_PATTERN)
            next unless match

            path = T.must(match[:double] || match[:single] || match[:plain])
            joined_path = current_directory == "." ? path : File.join(current_directory, path)
            normalize_path(joined_path)
          end
        end

        sig do
          params(
            requirements: T::Array[Dependabot::DependencyRequirement],
            requirement_string: String
          ).void
        end
        def write_dependency_files(requirements:, requirement_string:)
          dependency_files.each do |file|
            next unless file.content

            FileUtils.mkdir_p(File.dirname(file.name))
            content = resolver_file_content(file)
            requirements.select { |requirement| requirement.file == file.name }.each do |requirement|
              content = updated_requirement_content(content, requirement, requirement_string)
            end
            File.write(file.name, content)
          end
          File.write(".python-version", language_version_manager.python_major_minor)
        end

        sig { params(file: Dependabot::DependencyFile).returns(String) }
        def resolver_file_content(file)
          content = T.must(file.content)
          return content unless file.name.end_with?(*PIP_REQUIREMENT_FILE_EXTENSIONS)

          content.gsub(HASH_OPTION_PATTERN, "").gsub(REQUIRE_HASHES_PATTERN, "")
        end

        sig do
          params(
            content: String,
            requirement: Dependabot::DependencyRequirement,
            requirement_string: String
          ).returns(String)
        end
        def updated_requirement_content(content, requirement, requirement_string)
          FileUpdater::RequirementReplacer.new(
            content: content,
            dependency_name: dependency.name,
            old_requirement: requirement.requirement_string,
            new_requirement: requirement_string
          ).updated_content
        end

        sig do
          params(
            file: Dependabot::DependencyFile,
            requirement: Dependabot::DependencyRequirement
          ).returns(T::Boolean)
        end
        def requirement_declaration_present?(file, requirement)
          expected_requirement = T.must(requirement.requirement_string).gsub(/\s/, "")
          T.must(file.content).each_line.any? do |line|
            parsed = RequirementParser.parse(line)
            next false unless parsed

            parsed[:normalised_name] == NameNormaliser.normalise(dependency.name) &&
              parsed[:requirement]&.gsub(/\s/, "") == expected_requirement
          end
        end

        sig do
          params(
            root_file: Dependabot::DependencyFile,
            allow_prereleases: T::Boolean
          ).returns(String)
        end
        def pip_resolver_command(root_file, allow_prereleases:)
          command = [
            "pyenv", "exec", "pip", "install", "--dry-run", "--ignore-installed",
            "--report", PIP_REPORT_FILENAME
          ]
          command << "--pre" if allow_prereleases
          Shellwords.join([*command, "-r", root_file.name])
        end

        sig { returns(String) }
        def pip_resolver_fingerprint
          "pyenv exec pip install --dry-run --ignore-installed --report <report> -r <requirements_file>"
        end

        sig { returns(T::Hash[String, String]) }
        def pip_environment
          index_credentials = credentials.select { |credential| credential["type"] == "python_index" }
          environment = T.let({}, T::Hash[String, String])

          base_credential = index_credentials.find(&:replaces_base?)
          environment["PIP_INDEX_URL"] = AuthedUrlBuilder.authed_url(credential: base_credential) if base_credential

          extra_index_urls = index_credentials.reject(&:replaces_base?).map do |credential|
            AuthedUrlBuilder.authed_url(credential: credential)
          end
          environment["PIP_EXTRA_INDEX_URL"] = extra_index_urls.join(" ") if extra_index_urls.any?

          environment
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def pip_report_version
          report = T.cast(JSON.parse(File.read(PIP_REPORT_FILENAME)), T::Hash[String, Object])
          installs_obj = report["install"]
          return unless installs_obj.is_a?(Array)

          installs_obj.each do |entry|
            install = T.cast(entry, T.nilable(Object))
            next unless install.is_a?(Hash)

            metadata = T.cast(install["metadata"], T.nilable(Object))
            next unless metadata.is_a?(Hash)

            name = T.cast(metadata["name"], T.nilable(Object))
            version = T.cast(metadata["version"], T.nilable(Object))
            next unless name.is_a?(String) && version.is_a?(String)
            next unless NameNormaliser.normalise(name) == NameNormaliser.normalise(dependency.name)

            return Python::Version.new(version)
          end

          nil
        rescue JSON::ParserError, Errno::ENOENT
          nil
        end

        sig { params(candidate: Dependabot::Version).returns(T::Boolean) }
        def compatible_with_pinned_pyproject_dependencies?(candidate)
          return true unless constraints_dependency?

          pinned_dependencies = pinned_pyproject_dependencies
          return false if pinned_dependencies.none? && pyproject_scope_ambiguous_for_constraints?
          return true if pinned_dependencies.none?

          pinned_dependencies.all? do |name, version|
            requirements, metadata_available = transitive_requirement_for(name: name, version: version)
            next false unless metadata_available
            next true if requirements.empty?

            requirements.all? do |requirement|
              Python::Requirement.new(requirement).satisfied_by?(candidate)
            rescue Gem::Requirement::BadRequirementError
              # If one metadata requirement is unsupported, ignore it but still
              # enforce any other valid constraints for this dependency.
              true
            end
          end
        end

        sig { returns(T::Boolean) }
        def pyproject_scope_ambiguous_for_constraints?
          pyproject_files.length > 1 && relevant_pyproject_files_for_dependency.empty?
        end

        sig { returns(T::Boolean) }
        def constraints_dependency?
          normalized_requirement_files.any? do |raw_file, normalized_file|
            constraints_files.include?(normalized_file) ||
              (File.dirname(raw_file) == "." && constraints_file_basenames.include?(File.basename(normalized_file))) ||
              File.basename(normalized_file).start_with?("constraints")
          end
        end

        sig { returns(T::Array[[String, String]]) }
        def normalized_requirement_files
          dependency.requirements.filter_map do |req|
            raw_file = T.cast(req.fetch(:file), String)
            [raw_file, normalize_path(raw_file)]
          end
        end

        sig { returns(T::Array[[String, String]]) }
        def pinned_pyproject_dependencies
          pyprojects = relevant_pyproject_files_for_dependency
          return [] if pyprojects.empty?

          pyprojects.flat_map do |pyproject|
            pinned_pyproject_dependencies_for(pyproject)
          end.uniq
        end

        sig { params(pyproject: Dependabot::DependencyFile).returns(T::Array[[String, String]]) }
        def pinned_pyproject_dependencies_for(pyproject)
          pyproject_content = pyproject_content_for(pyproject)
          project_obj = pyproject_content["project"]
          return [] unless project_obj.is_a?(Hash)

          project_hash = project_obj
          dependencies_obj = T.cast(project_hash["dependencies"], T.nilable(Object))
          return [] unless dependencies_obj.is_a?(Array)

          dependencies_obj.filter_map do |entry|
            entry_obj = T.cast(entry, T.nilable(Object))
            next unless entry_obj.is_a?(String)

            requirement_string, marker = split_requirement_and_marker(entry_obj)
            next unless marker_satisfied_for_python?(marker)
            next if requirement_string.nil? || requirement_string.empty?

            parsed = requirement_string.match(
              /\A(?<name>[A-Za-z0-9][A-Za-z0-9._\-]*)(?:\[[^\]]+\])?\s*==\s*(?<version>[^\s]+)\z/
            )
            next unless parsed

            dep_name = NameNormaliser.normalise(T.must(parsed[:name]))
            next if dep_name == NameNormaliser.normalise(dependency.name)

            [dep_name, T.must(parsed[:version])]
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def relevant_pyproject_files_for_dependency
          requirement_files = requirement_files_for_dependency
          relevant_pyprojects = pyproject_files.select do |pyproject|
            pyproject_matches_requirement_files?(pyproject: pyproject, requirement_files: requirement_files)
          end

          return relevant_pyprojects unless relevant_pyprojects.empty?

          fallback_pyproject_for_dependency
        end

        sig { returns(T::Array[String]) }
        def requirement_files_for_dependency
          normalized_requirement_files.map(&:last).uniq
        end

        sig { params(pyproject: Dependabot::DependencyFile, requirement_files: T::Array[String]).returns(T::Boolean) }
        def pyproject_matches_requirement_files?(pyproject:, requirement_files:)
          declared_constraints = constraints_for_pyproject(pyproject)
          declared_constraints.any? do |declared_constraint|
            declared_constraint_matches_requirement_files?(
              declared_constraint: declared_constraint,
              requirement_files: requirement_files
            )
          end
        end

        sig { params(declared_constraint: String, requirement_files: T::Array[String]).returns(T::Boolean) }
        def declared_constraint_matches_requirement_files?(declared_constraint:, requirement_files:)
          return true if requirement_files.include?(declared_constraint)

          !url_path?(declared_constraint) &&
            File.dirname(declared_constraint) == "." &&
            constraints_file_basenames.include?(File.basename(declared_constraint)) &&
            requirement_files.include?(File.basename(declared_constraint))
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def fallback_pyproject_for_dependency
          return [T.must(pyproject_files.first)] if pyproject_files.length == 1

          []
        end

        sig { params(name: String, version: String).returns([T::Array[String], T::Boolean]) }
        def transitive_requirement_for(name:, version:)
          cache_key = "#{name}@#{version}"
          if @transitive_requirements_cache.key?(cache_key)
            requirements = T.must(@transitive_requirements_cache[cache_key])
            available = T.must(@transitive_requirement_available_cache[cache_key])
            return [requirements, available]
          end

          response, metadata_available = dependency_metadata_response(name: name, version: version)
          unless response
            @transitive_requirements_cache[cache_key] = []
            @transitive_requirement_available_cache[cache_key] = metadata_available
            return [[], metadata_available]
          end

          requirements, metadata_available = requirements_for_target_dependency(response)

          @transitive_requirements_cache[cache_key] = requirements
          @transitive_requirement_available_cache[cache_key] = metadata_available
          [requirements, metadata_available]
        end

        sig { params(name: String, version: String).returns([T.nilable(Excon::Response), T::Boolean]) }
        def dependency_metadata_response(name:, version:)
          had_transport_error = T.let(false, T::Boolean)
          saw_not_found = T.let(false, T::Boolean)

          registry_json_urls.each do |registry_url|
            url = "#{registry_url}#{name}/#{version}/json/"
            response = Dependabot::RegistryClient.get(url: url)
            return [response, true] if response.status == 200

            if response.status == 404
              saw_not_found = true
            else
              had_transport_error = true
              Dependabot.logger.warn(
                "Unexpected python dependency metadata response #{response.status} for #{name}@#{version}"
              )
            end
          rescue Excon::Error::Timeout, Excon::Error::Socket, URI::InvalidURIError
            had_transport_error = true
            Dependabot.logger.warn("Failed to fetch python dependency metadata for #{name}@#{version}")
            next
          end

          [nil, saw_not_found && !had_transport_error]
        end

        sig { returns(T::Array[String]) }
        def registry_json_urls
          return @registry_json_urls if @registry_json_urls

          package_registry_urls = Package::PackageRegistryFinder.new(
            dependency_files: dependency_files,
            credentials: credentials,
            dependency: dependency
          ).registry_urls

          @registry_json_urls =
            package_registry_urls
            .map { |url| url.sub(%r{/simple/?$}i, "/pypi/") }
            .uniq

          @registry_json_urls
        end

        sig { params(response: Excon::Response).returns([T::Array[String], T::Boolean]) }
        def requirements_for_target_dependency(response)
          requires_dist = requires_dist_from_response(response)
          return [[], true] unless requires_dist

          parsed_requirements = requires_dist.filter_map do |requirement_string|
            parse_target_requirement(requirement_string)
          end.uniq

          [parsed_requirements, true]
        rescue JSON::ParserError
          Dependabot.logger.warn("Failed to parse python dependency metadata JSON response")
          [[], false]
        end

        sig { returns(T::Array[String]) }
        def constraints_files
          return @constraints_files if @constraints_files

          pyproject_constraints = pyproject_constraints_files
          requirement_constraints = requirement_constraint_declaration_files.flat_map do |file|
            requirement_constraints_from_file(file)
          end

          @constraints_files = (pyproject_constraints + requirement_constraints).map do |path|
            normalize_path(path)
          end.uniq
          @constraints_files
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def requirement_constraint_declaration_files
          requirement_paths = requirement_files_for_dependency
          directories = requirement_file_directories

          dependency_files.select do |file|
            next false unless requirements_manifest_file?(file)

            normalized_name = normalize_path(file.name)

            requirement_paths.include?(normalized_name) ||
              directories.include?(File.dirname(normalized_name))
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Boolean) }
        def requirements_manifest_file?(file)
          basename = File.basename(normalize_path(file.name))
          return true if basename.start_with?("requirements")

          false
        end

        sig { returns(T::Array[String]) }
        def requirement_file_directories
          return @requirement_file_directories if @requirement_file_directories

          @requirement_file_directories = requirement_files_for_dependency.filter_map do |path|
            next if url_path?(path)

            File.dirname(path)
          end.uniq
          @requirement_file_directories
        end

        sig { returns(T::Array[String]) }
        def constraints_file_basenames
          return @constraints_file_basenames if @constraints_file_basenames

          counts = T.let(Hash.new(0), T::Hash[String, Integer])
          constraints_files.each do |path|
            next if url_path?(path)

            counts[File.basename(path)] = T.must(counts[File.basename(path)]) + 1
          end
          @constraints_file_basenames = counts.filter_map do |basename, count|
            basename if count == 1
          end
          @constraints_file_basenames
        end

        sig { returns(T::Array[String]) }
        def pyproject_constraints_files
          pyproject_files.flat_map do |pyproject|
            constraints_for_pyproject(pyproject)
          end
        end

        sig { params(pyproject: Dependabot::DependencyFile).returns(T::Array[String]) }
        def constraints_for_pyproject(pyproject)
          pyproject_content = pyproject_content_for(pyproject)
          tool_obj = pyproject_content["tool"]
          return [] unless tool_obj.is_a?(Hash)

          pip_obj = T.cast(tool_obj["pip"], T.nilable(Object))
          return [] unless pip_obj.is_a?(Hash)

          constraints_obj = T.cast(pip_obj["constraints"], T.nilable(Object))
          case constraints_obj
          when String
            [resolve_constraint_path(path: constraints_obj, declaring_file: pyproject)]
          when Array
            constraints_obj.grep(String).map do |path|
              resolve_constraint_path(path: path, declaring_file: pyproject)
            end
          else
            []
          end
        end

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        def pyproject_files
          dependency_files.select do |file|
            File.basename(file.name) == "pyproject.toml"
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Array[String]) }
        def requirement_constraints_from_file(file)
          content = file.content
          return [] unless content

          content.each_line.filter_map do |line|
            path = constraint_path_from_line(line)
            next unless path

            resolve_constraint_path(path: path.strip, declaring_file: file)
          end
        end

        sig { params(line: String).returns(T.nilable(String)) }
        def constraint_path_from_line(line)
          match = line.match(
            /^\s*(?:-c|--constraint)(?:\s+|=)(?:"(?<double>[^"]+)"|'(?<single>[^']+)'|(?<plain>[^\s'\"]+))/
          )
          return nil unless match

          T.must(match[:double] || match[:single] || match[:plain])
        end

        sig { params(path: String, declaring_file: Dependabot::DependencyFile).returns(String) }
        def resolve_constraint_path(path:, declaring_file:)
          return path if url_path?(path)
          return normalize_path(path) if Pathname.new(path).absolute?

          base_dir = File.dirname(declaring_file.name)
          return normalize_path(path) if base_dir == "."

          normalize_path(File.join(base_dir, path))
        end

        sig { params(path: String).returns(String) }
        def normalize_path(path)
          return path if url_path?(path)

          Pathname.new(path).cleanpath.to_s
        rescue ArgumentError
          path
        end

        sig { params(path: String).returns(T::Boolean) }
        def url_path?(path)
          path.match?(%r{\A[a-z][a-z0-9+.-]*://}i)
        end

        sig { params(response: Excon::Response).returns(T.nilable(T::Array[String])) }
        def requires_dist_from_response(response)
          body = T.cast(JSON.parse(response.body), T::Hash[String, Object])
          info_obj = body["info"]
          return nil unless info_obj.is_a?(Hash)

          requires_dist_obj = T.cast(info_obj["requires_dist"], T.nilable(Object))
          return nil unless requires_dist_obj.is_a?(Array)

          requires_dist_obj.filter_map do |entry|
            entry_obj = T.cast(entry, T.nilable(Object))
            entry_obj if entry_obj.is_a?(String)
          end
        end

        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def parse_target_requirement(requirement_string)
          package_requirement, marker = split_requirement_and_marker(requirement_string)
          return nil unless marker_satisfied_for_python?(marker)
          return nil if package_requirement.nil?

          match = package_requirement.match(
            /\A(?<name>[A-Za-z0-9][A-Za-z0-9._\-]*)(?:\[[^\]]+\])?\s*(?:\((?<requirement>[^)]*)\))?\z/
          )
          return nil unless match

          return nil unless NameNormaliser.normalise(T.must(match[:name])) == NameNormaliser.normalise(dependency.name)

          match[:requirement]&.strip
        end

        sig { params(requirement_string: String).returns([T.nilable(String), T.nilable(String)]) }
        def split_requirement_and_marker(requirement_string)
          marker_evaluator.split_requirement_and_marker(requirement_string)
        end

        sig { params(marker: T.nilable(String)).returns(T::Boolean) }
        def marker_satisfied_for_python?(marker)
          return true if marker.nil? || marker.empty?
          return false unless marker.match?(/\bpython(?:_full)?_version\b/)

          marker_satisfied?(marker, language_version_manager.python_version)
        end

        sig { params(marker: String, python_version: String).returns(T::Boolean) }
        def marker_satisfied?(marker, python_version)
          marker_evaluator.marker_satisfied?(marker: marker, python_version: python_version)
        end

        sig { params(pyproject: Dependabot::DependencyFile).returns(T::Hash[String, Object]) }
        def pyproject_content_for(pyproject)
          cache_key = pyproject.name
          return T.must(@pyproject_content_cache[cache_key]) if @pyproject_content_cache.key?(cache_key)

          content =
            if pyproject.content
              T.let(TomlRB.parse(pyproject.content), T::Hash[String, Object])
            else
              T.let({}, T::Hash[String, Object])
            end

          @pyproject_content_cache[cache_key] = content
          content
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          @pyproject_content_cache[pyproject.name] = {}
          T.must(@pyproject_content_cache[pyproject.name])
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
