# typed: strong
# frozen_string_literal: true

require "base64"
require "json"
require "dependabot/gradle/file_updater"

module Dependabot
  module Gradle
    class FileUpdater
      class TransitiveDependencyUpdater
        extend T::Sig

        VALIDATION_SCRIPT = <<~GRADLE
          def validation = new groovy.json.JsonSlurper().parseText(new String("%<data>s".decodeBase64(), "UTF-8"))
          allprojects {
            tasks.create("%<task>s") { }
          }
          gradle.projectsEvaluated {
            if (gradle.parent != null) {
              return
            }
            def remaining = validation.expectations.collect { it }
            gradle.rootProject.allprojects { target ->
              validation.expectations.findAll {
                new File(gradle.rootProject.projectDir, it.directory).canonicalFile == target.projectDir.canonicalFile
              }.each { expected ->
                def configuration = target.configurations.findByName(expected.configuration)
                if (configuration == null || !configuration.canBeResolved ||
                    !configuration.resolutionStrategy.dependencyLockingEnabled) {
                  throw new GradleException("Cannot validate locked configuration " + expected.configuration)
                }
                def result = configuration.incoming.resolutionResult
                result.allDependencies.each { dependency ->
                  if (dependency instanceof org.gradle.api.artifacts.result.UnresolvedDependencyResult) {
                    throw new GradleException("Cannot resolve updated lockfile", dependency.failure)
                  }
                }
                def selected = result.allComponents.find {
                  it.moduleVersion != null &&
                    it.moduleVersion.group + ":" + it.moduleVersion.name == validation.name
                }
                if (selected == null || selected.moduleVersion.version != expected.version) {
                  throw new GradleException("Updated lockfile did not resolve " + validation.name + ":" + expected.version)
                }
                remaining.remove(expected)
              }
            }
            if (!remaining.isEmpty()) {
              throw new GradleException("Could not validate all updated lockfile configurations")
            }
          }
        GRADLE

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            vulnerable_versions: T::Array[String],
            repo_contents_path: T.nilable(String)
          ).void
        end
        def initialize(dependency:, dependency_files:, vulnerable_versions:, repo_contents_path: nil)
          @dependency = dependency
          @dependency_files = dependency_files
          @vulnerable_versions = vulnerable_versions
          @repo_contents_path = repo_contents_path
        end

        sig { params(version: String).returns(T::Array[Dependabot::DependencyFile]) }
        def updated_dependency_files(version:)
          lockfiles = @dependency_files.select do |file|
            File.basename(file.name) == "gradle.lockfile" && target_entries(file).any?
          end
          if lockfiles.empty?
            raise Dependabot::DependencyFileNotResolvable, "No Gradle lockfile contains #{@dependency.name}"
          end

          updated_lockfiles = lockfiles.map do |file|
            updated_file = file.dup
            updated_file.content = updated_content(file, version)
            updated_file
          end
          validate_lockfiles(updated_lockfiles)

          updated_lockfiles.reject { |file| @dependency_files.include?(file) }
        end

        private

        sig { params(lockfiles: T::Array[Dependabot::DependencyFile]).void }
        def validate_lockfiles(lockfiles)
          replacements = lockfiles.to_h { |file| [file.name, file] }
          files = @dependency_files.map { |file| replacements.fetch(file.name, file) }
          validator = LockfileValidator.new(dependency_files: files, repo_contents_path: @repo_contents_path)
          grouped = lockfiles.group_by { |file| validator.determine_root_dir(build_file: file) }
          grouped.each do |root, root_files|
            validator.validate_lockfiles(
              T.must(root_files.first), validation_script: validation_script(root_files, root, validator)
            )
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Array[FileParser::LockfileParser::Entry]) }
        def target_entries(file)
          FileParser::LockfileParser.new(lockfile: file).entries.select do |entry|
            entry.name == @dependency.name && Gradle::Version.correct?(entry.version)
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(T::Array[FileParser::LockfileParser::Entry]) }
        def vulnerable_entries(file)
          target_entries(file).select { |entry| @vulnerable_versions.include?(entry.version) }
        end

        sig { params(match: MatchData, version: String).returns(T::Boolean) }
        def updatable_entry?(match, version)
          match[:name] == @dependency.name && Gradle::Version.correct?(match[:version]) &&
            (@vulnerable_versions.include?(match[:version]) || match[:version] == version)
        end

        sig { params(file: Dependabot::DependencyFile, version: String).returns(String) }
        def updated_content(file, version)
          return T.must(file.content) if vulnerable_entries(file).empty?

          configurations = updated_configurations(file, version)
          seen = T.let(Set.new, T::Set[String])

          T.must(file.content).lines.filter_map do |line|
            match = FileParser::LockfileParser::DEPENDENCY_REGEX.match(line.strip)
            next line unless match && updatable_entry?(match, version)

            target = target_version(T.must(match[:version]), version)
            next unless seen.add?(target)

            newline = line.end_with?("\r\n") ? "\r\n" : "\n"
            "#{@dependency.name}:#{target}=#{T.must(configurations[target]).join(',')}#{newline}"
          end.join
        end

        sig { params(file: Dependabot::DependencyFile, version: String).returns(T::Hash[String, T::Array[String]]) }
        def updated_configurations(file, version)
          configurations = T.let({}, T::Hash[String, T::Array[String]])
          target_entries(file).each do |entry|
            target = target_version(entry.version, version)
            configurations[target] = (configurations.fetch(target, []) + entry.configurations).uniq.sort
          end
          configurations
        end

        sig { params(current: String, candidate: String).returns(String) }
        def target_version(current, candidate)
          return current unless @vulnerable_versions.include?(current)

          [Gradle::Version.new(current), Gradle::Version.new(candidate)].max.to_s
        end

        sig do
          params(
            lockfiles: T::Array[Dependabot::DependencyFile],
            root: String,
            validator: LockfileValidator
          ).returns(String)
        end
        def validation_script(lockfiles, root, validator)
          expectations = lockfiles.flat_map do |file|
            directory = Pathname.new(validator.normalized_directory_path(file))
                                .relative_path_from(Pathname.new(root)).to_s
            target_entries(file).flat_map do |entry|
              entry.configurations.map do |configuration|
                { directory: directory, configuration: configuration, version: entry.version }
              end
            end
          end
          # Encoding data separately keeps Gradle coordinates and paths out of executable Groovy syntax.
          data = Base64.strict_encode64(JSON.generate(name: @dependency.name, expectations: expectations))

          format(VALIDATION_SCRIPT, data: data, task: LockfileUpdater::INIT_SCRIPT_TASK_NAME)
        end
      end
    end
  end
end
