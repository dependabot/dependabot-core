# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "toml-rb"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/logger"
require "dependabot/shared_helpers"
require "dependabot/cargo/file_updater"
require "dependabot/cargo/graph_transition_policy"
require "dependabot/cargo/lockfile_graph"
require "dependabot/cargo/version"

module Dependabot
  module Cargo
    class FileUpdater
      # Validates registry dependency updates by proving lock-graph edge
      # transitions between the original and final Cargo.lock. Anything the
      # policy cannot prove (status unknown) fails closed.
      class GraphUpdateValidator
        extend T::Sig

        Policy = Dependabot::Cargo::GraphTransitionPolicy

        BEFORE = "before"
        AFTER = "after"

        class Unproven < StandardError
          extend T::Sig

          sig { returns(Policy::Reason) }
          attr_reader :reason

          sig { params(reason: Policy::Reason).void }
          def initialize(reason)
            @reason = reason
            super(reason.message)
          end
        end
        private_constant :Unproven

        sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
        def self.covers?(dependency)
          previous_version = dependency.previous_version
          version = dependency.version
          return false unless previous_version && version

          Version.correct?(previous_version) && Version.correct?(version)
        end

        sig do
          params(
            dependencies: T::Array[Dependabot::Dependency],
            manifest_files: T::Array[Dependabot::DependencyFile],
            original_lockfile: Dependabot::DependencyFile,
            updated_lockfile: Dependabot::DependencyFile
          ).void
        end
        def initialize(dependencies:, manifest_files:, original_lockfile:, updated_lockfile:)
          @dependencies = dependencies
          @manifest_files = manifest_files
          @original_lockfile = original_lockfile
          @updated_lockfile = updated_lockfile
        end

        # Cargo either moves every consumer of the previous package, or splits
        # the graph so only the declaring manifests move while other consumers
        # keep the previous version. Each is proven as a separate exact claim;
        # a rejection under the unscoped claim is final.
        sig { void }
        def validate!
          return if @dependencies.empty?

          facts = lock_graph_facts
          # An unparsable snapshot has no packages, so report its diagnostics
          # before trying to resolve update identities against it.
          facts_check = evaluate(facts, [])
          fail_closed(facts_check) unless facts_check.reasons.all? { |reason| reason.code == "no_intents" }

          validate_transitions(facts)
        rescue Unproven => e
          fail_closed(Policy::Result.new(status: Policy::Status::Unknown, reasons: [e.reason]))
        end

        private

        sig { params(facts: T::Hash[String, Object]).void }
        def validate_transitions(facts)
          packages = before_packages(facts)
          previous = @dependencies.map { |dependency| previous_identity(dependency, packages) }

          unscoped = evaluate(facts, intents(previous) { nil })
          return if unscoped.status == Policy::Status::Accepted

          fail_closed(unscoped) if unscoped.status == Policy::Status::Rejected

          scoped_intents = intents(previous) { |dependency| declaring_parents(dependency, packages) }
          fail_closed(unscoped) if scoped_intents.all? { |intent| intent.parents.nil? }

          scoped = evaluate(facts, scoped_intents)
          return if scoped.status == Policy::Status::Accepted

          fail_closed(scoped, unscoped)
        end

        sig { returns(T::Hash[String, Object]) }
        def lock_graph_facts
          LockfileGraph.facts(snapshots: { BEFORE => @original_lockfile, AFTER => @updated_lockfile })
        rescue Dependabot::SharedHelpers::HelperSubprocessFailed => e
          raise Unproven, unknown_reason("lock_graph_failed", "Lock graph helper failed: #{e.message}")
        end

        sig { params(facts: T::Hash[String, Object], intents: T::Array[Policy::Intent]).returns(Policy::Result) }
        def evaluate(facts, intents)
          Policy.evaluate(facts: facts, intents: intents, before: BEFORE, after: AFTER)
        end

        sig do
          params(
            previous: T::Array[Policy::Package],
            blk: T.proc.params(dependency: Dependabot::Dependency).returns(T.nilable(T::Array[Policy::Package]))
          ).returns(T::Array[Policy::Intent])
        end
        def intents(previous, &blk)
          @dependencies.zip(previous).map do |dependency, package|
            intent = Policy::Intent.from_dependency(dependency: dependency, previous: T.must(package))
            Policy::Intent.new(previous: intent.previous, target: intent.target, parents: yield(dependency))
          end
        end

        # The workspace packages whose manifests declare the dependency.
        # Workspace-level declarations are inherited by members, so they (and
        # any manifest without a unique lockfile package) cannot be scoped.
        sig do
          params(dependency: Dependabot::Dependency, packages: T::Array[Policy::Package])
            .returns(T.nilable(T::Array[Policy::Package]))
        end
        def declaring_parents(dependency, packages)
          requirements = dependency.requirements
          return nil if requirements.empty?
          return nil if requirements.any? { |req| Array(req[:groups]).include?("workspace.dependencies") }

          parents = requirements.map { |req| T.cast(req[:file], String) }.uniq.map do |file|
            parent = declaring_parent(file, packages)
            return nil unless parent

            parent
          end
          parents.uniq(&:key)
        end

        sig { params(file_name: String, packages: T::Array[Policy::Package]).returns(T.nilable(Policy::Package)) }
        def declaring_parent(file_name, packages)
          content = @manifest_files.find { |file| file.name == file_name }&.content
          return nil unless content

          name = TomlRB.parse(content).dig("package", "name")
          matches = packages.select { |package| package.source.nil? && package.name == name }
          matches.one? ? matches.first : nil
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          nil
        end

        # Prefer the exact source recorded by the file parser. Without it,
        # accept only a unique registry identity at the previous version;
        # source-less (path/workspace) and git packages never qualify.
        sig do
          params(dependency: Dependabot::Dependency, packages: T::Array[Policy::Package]).returns(Policy::Package)
        end
        def previous_identity(dependency, packages)
          source = T.cast(dependency.metadata[:cargo_package_source], T.nilable(String))
          candidates = packages.select do |package|
            package.name == dependency.name && package.version == dependency.previous_version &&
              (source ? package.source == source : registry_source?(package.source))
          end
          return T.must(candidates.first) if candidates.one?

          message = "Expected exactly one registry package #{dependency.name} #{dependency.previous_version} " \
                    "in the original Cargo.lock, found #{candidates.size}"
          raise Unproven, unknown_reason("previous_identity_unresolved", message)
        end

        sig { params(source: T.nilable(String)).returns(T::Boolean) }
        def registry_source?(source)
          return false unless source

          source.start_with?("registry+", "sparse+")
        end

        sig { params(facts: T::Hash[String, Object]).returns(T::Array[Policy::Package]) }
        def before_packages(facts)
          snapshots = facts["snapshots"]
          return [] unless snapshots.is_a?(Array)

          before = snapshots.find { |snapshot| snapshot.is_a?(Hash) && snapshot["name"] == BEFORE }
          packages = before.is_a?(Hash) ? before["packages"] : nil
          return [] unless packages.is_a?(Array)

          packages.filter_map do |package|
            next unless package.is_a?(Hash)

            Policy::Package.from_hash(package)
          rescue ArgumentError, TypeError
            nil
          end
        end

        sig { params(code: String, message: String).returns(Policy::Reason) }
        def unknown_reason(code, message)
          Policy::Reason.new(status: Policy::Status::Unknown, code: code, message: message)
        end

        sig { params(results: Policy::Result).returns(T.noreturn) }
        def fail_closed(*results)
          status = T.must(results.first).status.serialize
          details = results.flat_map(&:reasons)
                           .reject { |reason| reason.status == Policy::Status::Accepted }
                           .map { |reason| describe(reason) }.uniq.join("; ")
          Dependabot.logger.warn("Cargo lock graph validation #{status}: #{details}")
          raise Dependabot::UpdateNotPossible, @dependencies.map(&:name).uniq
        end

        sig { params(reason: Policy::Reason).returns(String) }
        def describe(reason)
          parts = [reason.code]
          parts << "previous=#{package_label(reason.previous)}" if reason.previous
          parts << "parent=#{package_label(reason.parent)}" if reason.parent
          parts << "observed=#{package_label(reason.observed)}" if reason.observed
          parts << "snapshot=#{reason.snapshot}" if reason.snapshot
          parts << reason.message.split.join(" ") if reason.parent.nil? && reason.observed.nil?
          parts.join(" ")
        end

        sig { params(package: T.nilable(Policy::Package)).returns(String) }
        def package_label(package)
          return "none" unless package

          "#{package.name}@#{package.version}"
        end
      end
    end
  end
end
