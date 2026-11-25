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
require "dependabot/python/dependency_grapher/requirements_layers"
require "dependabot/python/language_version_manager"
require "dependabot/python/name_normaliser"
require "dependabot/python/package/package_registry_finder"
require "dependabot/python/requirement"
require "dependabot/python/requirements_file_parser"
require "dependabot/python/update_checker"
require "dependabot/python/update_checker/latest_version_finder"
require "dependabot/python/file_parser/python_requirement_parser"
require "dependabot/python/file_parser/pyproject_document"
require "dependabot/python/marker_evaluator"

module Dependabot
  module Python
    class UpdateChecker
      # This resolver intentionally co-locates resolution, marker handling, and
      # constraints matching to keep compatibility decisions in one place.
      # rubocop:disable-next Metrics/ClassLength
      class PipVersionResolver
        extend T::Sig

        PIP_REPORT_FILENAME = "dependabot-pip-report.json"
        PIP_RESOLVER_FINGERPRINT =
          "pyenv exec pip install --dry-run --ignore-installed --report <report> -r <requirements_file>"
        RESOLUTION_ERROR_PATTERN = /ResolutionImpossible|No matching distribution found/
        NO_MATCHING_DISTRIBUTION_PATTERN =
          /No\s+matching\s+distribution\s+found\s+for\s+
           (?<name>[A-Za-z0-9][A-Za-z0-9._-]*)
           (?:\[[^\]\r\n]+\])?
           (?<requirement>[^\r\n]*)/x
        UNSUPPORTED_BUILD_METADATA_PATTERNS = T.let(
          [
            /Failed to build '.+' when getting requirements to build wheel/,
            /BackendUnavailable: Cannot import 'setuptools\.build_meta'/
          ].freeze,
          T::Array[Regexp]
        )
        PRERELEASE_OPT_IN_REQUIREMENT = ">=0.0.dev0"
        LOWER_BOUND_OPERATORS = %w(> >= ~>).freeze
        NON_PYTHON_MARKER_PATTERN =
          /\b(?:extra|implementation_name|implementation_version|os_name|platform_machine|
               platform_python_implementation|platform_release|platform_system|
               platform_version|sys_platform)\b/x
        MARKER_MEMBERSHIP_PATTERN = /\b(?:not\s+)?in\b/
        UNSUPPORTED_PYTHON_MARKER_OPERATOR_PATTERN =
          /\bpython(?:_full)?_version\b\s*(?:~=|===)/
        WILDCARD_PYTHON_MARKER_PATTERN =
          /\bpython(?:_full)?_version\b\s*(?:==|!=)\s*['"][^'"]*\*[^'"]*['"]/
        REVERSED_PYTHON_MARKER_PATTERN =
          /['"][^'"]*['"]\s*(?:<=|>=|==|!=|~=|===|<|>)\s*python(?:_full)?_version\b/
        VARIABLE_TO_VARIABLE_PYTHON_MARKER_PATTERN =
          /\bpython(?:_full)?_version\b\s*(?:<=|>=|==|!=|~=|===|<|>)\s*python(?:_full)?_version\b/
        PYTHON_SPLITLINES_BOUNDARY_PATTERN =
          /(?<=\r\n)|(?<=\r)(?!\n)|(?<!\r)(?<=\n)|(?<=[\v\f\x1C-\x1E\u0085\u2028\u2029])/
        PYTHON_LINE_ENDING_PATTERN = /(?:\r\n|[\n\v\f\r\x1C-\x1E\u0085\u2028\u2029])\z/
        LowerBound = T.type_alias { [String, Gem::Version] }
        ObjectHash = T.type_alias { T::Hash[String, Object] }

        class InvalidPipReport < Dependabot::DependabotError; end

        class ResolutionContext < T::ImmutableStruct
          const :declarations, T::Array[RequirementsFileParser::Declaration]
          const :root, String
          const :unchanged_declarations, T::Array[RequirementsFileParser::Declaration]
        end

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
          @marker_evaluator = T.let(nil, T.nilable(Dependabot::Python::MarkerEvaluator))
          @registry_json_urls = T.let(nil, T.nilable(T::Array[String]))
          @transitive_requirements_cache = T.let({}, T::Hash[String, T::Array[String]])
          @transitive_requirement_available_cache = T.let({}, T::Hash[String, T::Boolean])
          @constraints_files = T.let(nil, T.nilable(T::Array[String]))
          @constraints_file_basenames = T.let(nil, T.nilable(T::Array[String]))
          @requirement_file_directories = T.let(nil, T.nilable(T::Array[String]))
          @pyproject_document_cache = T.let({}, T::Hash[String, FileParser::PyprojectDocument])
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_resolvable_version
          language_version = language_version_manager.python_version
          eligible_versions = latest_version_finder.eligible_versions(
            language_version: language_version
          )
          policy_ceiling = eligible_versions.max
          return if policy_ceiling.nil?

          selection_requirement = resolver_requirement(policy_ceiling, eligible_versions, language_version)
          policy_candidate = eligible_versions.sort.reverse.find do |candidate|
            candidate_admitted_by_requirement?(candidate, selection_requirement)
          end
          policy_candidate ||= policy_ceiling if below_resolver_lower_bound?(policy_ceiling)
          return unless policy_candidate

          requirement_string = resolver_requirement(policy_candidate, eligible_versions, language_version)
          candidate = pip_resolvable_version(
            policy_candidate: policy_candidate,
            requirement_string: requirement_string
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
          candidates = latest_version_finder.eligible_security_fix_versions(
            language_version: language_version_manager.python_version
          )
          candidates.each do |candidate|
            resolved_candidate = pip_resolvable_version(
              policy_candidate: candidate,
              requirement_string: ["==#{candidate}", *source_exclusion_requirements].uniq.join(",")
            )
            next unless resolved_candidate == candidate
            return candidate if compatible_with_pinned_pyproject_dependencies?(candidate)
          end

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

        sig { returns(Dependabot::Python::MarkerEvaluator) }
        def marker_evaluator
          @marker_evaluator ||= Dependabot::Python::MarkerEvaluator.new
        end

        sig do
          params(
            policy_candidate: Dependabot::Version,
            requirement_string: String
          ).returns(T.nilable(Dependabot::Version))
        end
        def pip_resolvable_version(policy_candidate:, requirement_string:)
          return policy_candidate if local_version_bounds?(policy_candidate)
          return policy_candidate if below_resolver_lower_bound?(policy_candidate)

          context = resolution_context
          return policy_candidate unless context

          SharedHelpers.in_a_temporary_directory do
            SharedHelpers.with_git_configured(credentials: credentials) do
              write_dependency_files(context: context, requirement_string: requirement_string)
              language_version_manager.install_required_python
              SharedHelpers.run_shell_command(
                pip_resolver_command(context.root),
                allow_unsafe_shell_command: true,
                env: pip_environment,
                fingerprint: PIP_RESOLVER_FINGERPRINT,
                stderr_to_stdout: true
              )

              pip_report_version(
                context: context,
                policy_candidate: policy_candidate,
                requirement_string: requirement_string
              )
            end
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          return policy_candidate if UNSUPPORTED_BUILD_METADATA_PATTERNS.any? { |pattern| e.message.match?(pattern) }
          return policy_candidate if context && unchanged_peer_distribution_missing?(e.message, context)
          return nil if e.message.match?(RESOLUTION_ERROR_PATTERN)

          raise
        end

        sig { params(message: String, context: ResolutionContext).returns(T::Boolean) }
        def unchanged_peer_distribution_missing?(message, context)
          match = message.match(NO_MATCHING_DISTRIBUTION_PATTERN)
          return false unless match

          missing_name = NameNormaliser.normalise(T.must(match[:name]))
          missing_requirement = normalized_requirement(T.must(match[:requirement]))

          context.unchanged_declarations.any? do |declaration|
            next false if declaration.constraint
            next false unless marker_satisfied_for_python?(declaration.markers)
            next false unless NameNormaliser.normalise(declaration.name) == missing_name

            normalized_requirement(declaration.requirement.to_s) == missing_requirement
          end
        end

        sig { params(requirement: String).returns(String) }
        def normalized_requirement(requirement)
          normalized = requirement.gsub(/\s+/, "")
          return T.must(normalized[1...-1]) if normalized.start_with?("(") && normalized.end_with?(")")

          normalized
        end

        sig { returns(T.nilable(LowerBound)) }
        def resolver_lower_bound
          current_version = dependency.numeric_version
          return [">=", current_version] if current_version

          lower_bounds = dependency.requirements.filter_map { |requirement| lower_bound_for(requirement) }
          lower_bounds.max_by { |operator, version| [version, operator == ">" ? 1 : 0] }
        end

        sig { params(policy_candidate: Dependabot::Version).returns(T::Boolean) }
        def below_resolver_lower_bound?(policy_candidate)
          lower_bound = resolver_lower_bound
          return false unless lower_bound

          operator, version = lower_bound
          policy_candidate < version || (policy_candidate == version && operator == ">")
        end

        sig { params(requirement: Dependabot::DependencyRequirement).returns(T.nilable(LowerBound)) }
        def lower_bound_for(requirement)
          requirement_string = requirement.requirement_string
          return unless requirement_string

          parsed_requirements = T.let(
            Python::Requirement.new(requirement_string).requirements,
            T::Array[[String, Gem::Version]]
          )
          lower_bounds = parsed_requirements.filter_map do |operator, version|
            [operator, version] if LOWER_BOUND_OPERATORS.include?(operator)
          end
          operator, version = lower_bounds.max_by do |bound_operator, bound_version|
            [bound_version, bound_operator == ">" ? 1 : 0]
          end
          return unless operator && version

          [operator == ">" ? ">" : ">=", version]
        rescue Gem::Requirement::BadRequirementError
          nil
        end

        sig do
          params(
            policy_candidate: Dependabot::Version,
            eligible_versions: T::Array[Dependabot::Version],
            language_version: T.nilable(T.any(String, Dependabot::Version))
          ).returns(String)
        end
        def resolver_requirement(policy_candidate, eligible_versions, language_version)
          requirements = ["<=#{policy_candidate}"]
          lower_bound = resolver_lower_bound
          requirements.unshift("#{lower_bound[0]}#{lower_bound[1]}") if lower_bound
          requirements << "!=#{dependency.numeric_version}" if dependency.numeric_version
          requirements.concat(source_exclusion_requirements)
          requirements.concat(excluded_version_requirements(policy_candidate, eligible_versions, language_version))
          requirements << PRERELEASE_OPT_IN_REQUIREMENT if eligible_versions.any?(&:prerelease?)
          requirements.uniq.join(",")
        end

        sig do
          params(
            policy_candidate: Dependabot::Version,
            eligible_versions: T::Array[Dependabot::Version],
            language_version: T.nilable(T.any(String, Dependabot::Version))
          ).returns(T::Array[String])
        end
        def excluded_version_requirements(policy_candidate, eligible_versions, language_version)
          lower_bound = resolver_lower_bound
          excluded_versions = latest_version_finder.resolver_excluded_versions(language_version: language_version)

          excluded_versions.filter_map do |version|
            next if version > policy_candidate

            if lower_bound
              operator, bound_version = lower_bound
              next if version < bound_version || (version == bound_version && operator == ">")
            end
            next if eligible_versions.include?(version)

            "!=#{version}"
          end
        end

        sig { returns(T::Array[String]) }
        def source_exclusion_requirements
          dependency.requirements.flat_map do |requirement|
            requirement_string = requirement.requirement_string
            next [] unless requirement_string

            requirement_string.split(",").filter_map do |clause|
              exclusion = clause.strip
              exclusion if exclusion.start_with?("!=")
            end
          end.uniq
        end

        sig { params(candidate: Dependabot::Version, requirement_string: String).returns(T::Boolean) }
        def candidate_admitted_by_requirement?(candidate, requirement_string)
          wildcard_exclusions, requirements = requirement_string.split(",").map(&:strip).partition do |requirement|
            requirement.start_with?("!=") && requirement.end_with?(".*")
          end
          return false unless Dependabot::Python::Requirement.new(requirements.join(",")).satisfied_by?(candidate)

          wildcard_exclusions.none? do |exclusion|
            prefix = exclusion.delete_prefix("!=").delete_suffix(".*").strip
            wildcard_excludes_candidate?(candidate, prefix)
          end
        end

        sig { params(candidate: Dependabot::Version, prefix: String).returns(T::Boolean) }
        def wildcard_excludes_candidate?(candidate, prefix)
          candidate_version = Dependabot::Python::Version.new(candidate.to_s)
          prefix_version = Dependabot::Python::Version.new(prefix)
          candidate_release = candidate_version.release_segment.dup
          if candidate_release.length < prefix_version.release_segment.length
            candidate_release.fill(0, candidate_release.length...prefix_version.release_segment.length)
          end

          candidate_version.epoch == prefix_version.epoch &&
            candidate_release.first(prefix_version.release_segment.length) ==
              prefix_version.release_segment
        end

        sig { returns(T.nilable(ResolutionContext)) }
        def resolution_context
          requirement = native_dependency_requirement
          return unless requirement

          manifest_files = resolver_manifest_files
          result = RequirementsFileParser.new(
            dependency_files: dependency_files,
            requirement_files: (manifest_files + [T.must(requirement.file)]).uniq
          ).parse
          declaration = primary_declaration(result, requirement)
          return unless declaration&.requirement

          component = complete_primary_component(result, declaration, manifest_files)
          return unless component

          return if native_component_unsupported?(component, result.declarations)

          unchanged_declarations = result.declarations.filter_map do |item|
            next unless component.files.include?(item.file)
            next if NameNormaliser.normalise(item.name) == NameNormaliser.normalise(dependency.name)

            item
          end

          ResolutionContext.new(
            declarations: [declaration],
            root: T.must(component.roots.first),
            unchanged_declarations: unchanged_declarations
          )
        end

        sig do
          params(
            result: RequirementsFileParser::Result,
            declaration: RequirementsFileParser::Declaration,
            manifest_files: T::Array[String]
          ).returns(T.nilable(RequirementsFileParser::Component))
        end
        def complete_primary_component(result, declaration, manifest_files)
          file_node = result.files.find { |file| file.path == declaration.file }
          component = result.components.find { |item| item.id == file_node&.component_id }
          return unless component&.complete? && component.roots.one?
          return unless manifest_files.include?(T.must(component.roots.first))

          component
        end

        sig do
          params(
            result: RequirementsFileParser::Result,
            requirement: Dependabot::DependencyRequirement
          ).returns(T.nilable(RequirementsFileParser::Declaration))
        end
        def primary_declaration(result, requirement)
          normalized_file = Pathname.new(T.must(requirement.file)).cleanpath.to_s
          declarations = result.declarations.select do |declaration|
            declaration.file == normalized_file &&
              declaration.requirement == requirement.requirement_string &&
              NameNormaliser.normalise(declaration.name) == NameNormaliser.normalise(dependency.name)
          end
          declarations.first if declarations.one?
        end

        sig { returns(T.nilable(Dependabot::DependencyRequirement)) }
        def native_dependency_requirement
          return unless dependency.package_manager == "pip"
          return unless dependency.requirements.one?
          return unless dependency_file_paths_safe?

          requirement = T.must(dependency.requirements.first)
          requirement_file = requirement.file
          return unless requirement_file&.end_with?(".txt")
          return unless requirement.source.nil? && requirement.requirement_string

          return unless dependency_file_present?(requirement_file)

          requirement
        end

        sig { params(path: String).returns(T::Boolean) }
        def dependency_file_present?(path)
          normalized_path = Pathname.new(path).cleanpath.to_s
          dependency_files.any? do |file|
            file.content && Pathname.new(file.name).cleanpath.to_s == normalized_path
          end
        end

        sig do
          params(
            component: RequirementsFileParser::Component,
            declarations: T::Array[RequirementsFileParser::Declaration]
          ).returns(T::Boolean)
        end
        def native_component_unsupported?(component, declarations)
          return true unless component.source_spans_applicable
          return true if component.has_index_options && python_index_credentials?
          return true if pip_config_extra_indexes_override_credentials?
          return true if non_native_registry_sources?

          declarations.any? do |declaration|
            component.files.include?(declaration.file) && unsupported_declaration?(declaration)
          end
        end

        sig { params(declaration: RequirementsFileParser::Declaration).returns(T::Boolean) }
        def unsupported_declaration?(declaration)
          declaration.editable ||
            declaration.local ||
            declaration.hashes.any? ||
            unsupported_marker?(declaration.markers)
        end

        sig { params(marker: T.nilable(String)).returns(T::Boolean) }
        def unsupported_marker?(marker)
          return false unless marker

          [
            NON_PYTHON_MARKER_PATTERN,
            MARKER_MEMBERSHIP_PATTERN,
            UNSUPPORTED_PYTHON_MARKER_OPERATOR_PATTERN,
            WILDCARD_PYTHON_MARKER_PATTERN,
            REVERSED_PYTHON_MARKER_PATTERN,
            VARIABLE_TO_VARIABLE_PYTHON_MARKER_PATTERN
          ].any? { |pattern| marker.match?(pattern) }
        end

        sig { returns(T::Boolean) }
        def python_index_credentials?
          credentials.any? { |credential| credential["type"] == "python_index" }
        end

        sig { returns(T::Boolean) }
        def pip_config_extra_indexes_override_credentials?
          return false unless credentials.any? do |credential|
            credential["type"] == "python_index" && !credential.replaces_base?
          end

          pip_config = dependency_files.find { |file| file.name == "pip.conf" }
          pip_config&.content&.match?(/^\s*extra-index-url\s*=/i) == true
        end

        sig { returns(T::Boolean) }
        def non_native_registry_sources?
          native_dependency_files = dependency_files.reject do |file|
            file.name == "Pipfile" || file.name == "pyproject.toml"
          end
          package_registry_urls(dependency_files) != package_registry_urls(native_dependency_files)
        end

        sig { returns(T::Boolean) }
        def dependency_file_paths_safe?
          dependency_files.all? do |file|
            path = Pathname.new(file.name).cleanpath
            !path.absolute? && path.each_filename.first != ".."
          end
        end

        sig { returns(T::Array[String]) }
        def resolver_manifest_files
          dependency_files.filter_map do |file|
            file.name if file.name.end_with?(".in") ||
                         DependencyGrapher::RequirementsLayers.manifest_txt_filename?(file.name)
          end
        end

        sig { params(policy_candidate: Dependabot::Version).returns(T::Boolean) }
        def local_version_bounds?(policy_candidate)
          policy_candidate.to_s.include?("+") || resolver_lower_bound&.last&.to_s&.include?("+") == true
        end

        sig do
          params(
            context: ResolutionContext,
            requirement_string: String
          ).void
        end
        def write_dependency_files(context:, requirement_string:)
          declarations_by_file = context.declarations.group_by(&:file)
          dependency_files.each do |file|
            next unless file.content

            FileUtils.mkdir_p(File.dirname(file.name))
            normalized_file = Pathname.new(file.name).cleanpath.to_s
            declarations = declarations_by_file.fetch(normalized_file, [])
            content = replace_declaration_spans(T.must(file.content), declarations, requirement_string)
            File.write(file.name, content)
          end
          File.write(".python-version", language_version_manager.python_major_minor)
        end

        sig do
          params(
            content: String,
            declarations: T::Array[RequirementsFileParser::Declaration],
            requirement_string: String
          ).returns(String)
        end
        def replace_declaration_spans(content, declarations, requirement_string)
          lines = content.split(PYTHON_SPLITLINES_BOUNDARY_PATTERN)
          declarations.sort_by { |declaration| declaration.source.start_line }.reverse_each do |declaration|
            start_index = declaration.source.start_line - 1
            length = declaration.source.end_line - declaration.source.start_line + 1
            ending = line_ending(lines.fetch(start_index + length - 1))
            extras = declaration.extras.any? ? "[#{declaration.extras.join(',')}]" : ""
            marker = declaration.markers
            marker = nil if marker == "None"
            marker_suffix = marker ? "; #{marker}" : ""
            replacement = "#{declaration.name}#{extras}#{requirement_string}#{marker_suffix}#{ending}"
            lines[start_index, length] = [replacement]
          end
          lines.join
        end

        sig { params(line: String).returns(String) }
        def line_ending(line)
          line[PYTHON_LINE_ENDING_PATTERN] || ""
        end

        sig { params(root: String).returns(String) }
        def pip_resolver_command(root)
          command = [
            "pyenv", "exec", "pip", "install", "--dry-run", "--ignore-installed",
            "--report", PIP_REPORT_FILENAME
          ]
          Shellwords.join([*command, "-r", root])
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
          if dependency_files.any? { |file| file.name == "pip.conf" }
            environment["PIP_CONFIG_FILE"] = File.expand_path("pip.conf")
          end

          environment
        end

        sig do
          params(
            context: ResolutionContext,
            policy_candidate: Dependabot::Version,
            requirement_string: String
          ).returns(T.nilable(Dependabot::Version))
        end
        def pip_report_version(context:, policy_candidate:, requirement_string:)
          report_object = T.let(JSON.parse(File.read(PIP_REPORT_FILENAME)), Object)
          report = object_hash(report_object)
          raise InvalidPipReport, "pip report must be an object" unless report

          installs = report["install"]
          raise InvalidPipReport, "pip report install must be an array" unless installs.is_a?(Array)

          versions = installs.filter_map { |entry| version_from_pip_report_entry(T.cast(entry, Object)) }.uniq
          return T.must(versions.first) if versions.one?

          if versions.empty? && context.declarations.all?(&:constraint)
            return nil unless candidate_admitted_by_requirement?(policy_candidate, requirement_string)

            return policy_candidate
          end

          raise InvalidPipReport, "pip report did not contain exactly one version for #{dependency.name}"
        rescue JSON::ParserError, Errno::ENOENT => e
          raise InvalidPipReport, "invalid pip report: #{e.message}"
        end

        sig { params(entry: Object).returns(T.nilable(Dependabot::Version)) }
        def version_from_pip_report_entry(entry)
          install = object_hash(entry)
          raise InvalidPipReport, "pip report install entry must be an object" unless install

          metadata = object_hash(install["metadata"])
          raise InvalidPipReport, "pip report install metadata must be an object" unless metadata

          name = metadata["name"]
          version = metadata["version"]
          unless name.is_a?(String) && version.is_a?(String)
            raise InvalidPipReport, "pip report install metadata must contain a name and version"
          end
          return unless NameNormaliser.normalise(name) == NameNormaliser.normalise(dependency.name)

          Python::Version.new(version)
        rescue ArgumentError => e
          raise InvalidPipReport, "pip report contained an invalid version: #{e.message}"
        end

        sig { params(value: T.nilable(Object)).returns(T.nilable(ObjectHash)) }
        def object_hash(value)
          return unless value.is_a?(Hash)

          typed_value = T.let(value, T::Hash[Object, Object])
          typed_value.each_with_object(T.let({}, ObjectHash)) do |(key, item), result|
            result[key] = item if key.is_a?(String)
          end
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
            raw_file = req.file
            next unless raw_file

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
          pyproject_document_for(pyproject).pip_dependencies.filter_map do |entry|
            requirement_string, marker = split_requirement_and_marker(entry)
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

          @registry_json_urls =
            package_registry_urls(dependency_files)
            .map { |url| url.sub(%r{/simple/?$}i, "/pypi/") }
            .uniq
        end

        sig { params(files: T::Array[Dependabot::DependencyFile]).returns(T::Array[String]) }
        def package_registry_urls(files)
          Package::PackageRegistryFinder.new(
            dependency_files: files,
            credentials: credentials,
            dependency: dependency
          ).registry_urls
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
          pyproject_document_for(pyproject).pip_constraint_paths.map do |path|
            resolve_constraint_path(path: path, declaring_file: pyproject)
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
          return true if marker.nil? || marker.empty? || marker == "None"
          return false unless marker.match?(/\bpython(?:_full)?_version\b/)

          marker_satisfied?(marker, language_version_manager.python_version)
        end

        sig { params(marker: String, python_version: String).returns(T::Boolean) }
        def marker_satisfied?(marker, python_version)
          marker_evaluator.marker_satisfied?(marker: marker, python_version: python_version)
        end

        sig { params(pyproject: Dependabot::DependencyFile).returns(FileParser::PyprojectDocument) }
        def pyproject_document_for(pyproject)
          cache_key = pyproject.name
          return T.must(@pyproject_document_cache[cache_key]) if @pyproject_document_cache.key?(cache_key)

          content = pyproject.content
          document =
            if content
              FileParser::PyprojectDocument.from_content(content)
            else
              FileParser::PyprojectDocument.new({})
            end

          @pyproject_document_cache[cache_key] = document
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          @pyproject_document_cache[pyproject.name] = FileParser::PyprojectDocument.new({})
        end
      end
    end
  end
end
