# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/cargo/version"

module Dependabot
  module Cargo
    class GraphTransitionPolicy
      extend T::Sig

      class Package < T::Struct
        extend T::Sig

        const :name, String
        const :version, String
        const :source, T.nilable(String)

        sig { returns([String, String, T.nilable(String)]) }
        def key
          [name, version, source]
        end
      end

      class Edge < T::Struct
        const :from, Package
        const :to, Package
        const :kind, String
      end

      EDGE_KINDS = %w(dependency replacement).freeze

      class Diagnostic < T::Struct
        const :code, String
        const :message, String
        const :package, T.nilable(Package)
        const :reference, T.nilable(String)
        const :candidates, T::Array[Package]
      end

      class Snapshot < T::Struct
        const :name, String
        const :lockfile_version, T.nilable(Integer)
        const :complete, T::Boolean
        const :packages, T::Array[Package]
        const :edges, T::Array[Edge]
        const :diagnostics, T::Array[Diagnostic]
      end

      class Intent < T::Struct
        extend T::Sig

        const :previous, Package
        const :target, Package
        const :parents, T.nilable(T::Array[Package])

        sig { params(dependency: Dependency, previous: Package).returns(Intent) }
        def self.from_dependency(dependency:, previous:)
          unless dependency.package_manager == "cargo" && dependency.name == previous.name &&
                 dependency.previous_version == previous.version && dependency.version
            raise ArgumentError, "Cargo update must match the supplied previous identity and have a target version"
          end

          new(
            previous: previous,
            target: Package.new(name: previous.name, version: T.must(dependency.version), source: previous.source)
          )
        end
      end

      class Status < T::Enum
        enums do
          Accepted = new("accepted")
          Rejected = new("rejected")
          Unknown = new("unknown")
        end
      end

      class Reason < T::Struct
        const :status, Status
        const :code, String
        const :message, String
        const :snapshot, T.nilable(String)
        const :previous, T.nilable(Package)
        const :parent, T.nilable(Package)
        const :observed, T.nilable(Package)
        const :diagnostic, T.nilable(Diagnostic)
      end

      class Result < T::Struct
        const :status, Status
        const :reasons, T::Array[Reason]
      end

      sig do
        params(facts: T::Hash[String, Object], intents: T::Array[Intent], before: String, after: String).returns(Result)
      end
      def self.evaluate(facts:, intents:, before: "before", after: "after")
        return unknown("unsupported_schema", "Expected lock graph schema version 1") unless facts["schema_version"] == 1

        raw_snapshots = facts.fetch("snapshots")
        unless raw_snapshots.is_a?(Array) && raw_snapshots.all?(Hash)
          return unknown("malformed_facts", "Snapshots must be an array of objects")
        end

        snapshots = T.let(raw_snapshots, T::Array[T::Hash[String, Object]])
        old = snapshots.select { |snapshot| snapshot["name"] == before }
        updated = snapshots.select { |snapshot| snapshot["name"] == after }
        unless before != after && old.one? && updated.one?
          return unknown("snapshot_selection", "Before and after names must each identify exactly one snapshot")
        end

        new(
          before: Snapshot.from_hash(T.must(old.first), strict: true),
          after: Snapshot.from_hash(T.must(updated.first), strict: true),
          intents: intents
        ).validate
      rescue KeyError, ArgumentError, TypeError => e
        unknown("malformed_facts", e.message)
      end

      sig { params(code: String, message: String).returns(Result) }
      def self.unknown(code, message)
        Result.new(
          status: Status::Unknown,
          reasons: [Reason.new(status: Status::Unknown, code: code, message: message)]
        )
      end
      private_class_method :unknown

      sig { params(before: Snapshot, after: Snapshot, intents: T::Array[Intent]).void }
      def initialize(before:, after:, intents:)
        @before = before
        @after = after
        @intents = intents
      end

      sig { returns(Result) }
      def validate
        reasons = snapshot_reasons
        return result(reasons) unless reasons.empty?

        reasons = intent_reasons
        return result(reasons) unless reasons.empty?

        reasons = @intents.flat_map { |intent| transition_reasons(intent) } + unselected_reasons
        reasons << Reason.new(status: Status::Unknown, code: "no_intents", message: "No update intents supplied") if
          @intents.empty?
        result(reasons)
      end

      private

      sig { params(reasons: T::Array[Reason]).returns(Result) }
      def result(reasons)
        status = if reasons.any? { |reason| reason.status == Status::Rejected }
                   Status::Rejected
                 elsif reasons.any? { |reason| reason.status == Status::Unknown }
                   Status::Unknown
                 else
                   Status::Accepted
                 end
        Result.new(status: status, reasons: reasons)
      end

      sig { returns(T::Array[Reason]) }
      def snapshot_reasons
        [@before, @after].flat_map do |snapshot|
          reasons = snapshot.diagnostics.map do |diagnostic|
            Reason.new(
              status: Status::Unknown,
              code: diagnostic.code,
              message: diagnostic.message,
              snapshot: snapshot.name,
              previous: diagnostic.package,
              diagnostic: diagnostic
            )
          end
          unless valid_snapshot?(snapshot)
            reasons << Reason.new(
              status: Status::Unknown,
              code: "incomplete_facts",
              message: "Snapshot is incomplete or contains invalid identities or edges",
              snapshot: snapshot.name
            )
          end

          reasons
        end
      end

      sig { params(snapshot: Snapshot).returns(T::Boolean) }
      def valid_snapshot?(snapshot)
        keys = snapshot.packages.map(&:key)
        valid_edges = snapshot.edges.all? do |edge|
          EDGE_KINDS.include?(edge.kind) && keys.include?(edge.from.key) && keys.include?(edge.to.key)
        end
        valid_versions = snapshot.packages.all? { |pkg| !pkg.version.empty? && Version.correct?(pkg.version) }
        snapshot.complete && keys.uniq.size == keys.size && valid_edges && valid_versions
      end

      sig { returns(T::Array[Reason]) }
      def intent_reasons
        @intents.filter_map do |intent|
          code = intent_code(intent)
          next unless code

          Reason.new(
            status: code == "requested_downgrade" ? Status::Rejected : Status::Unknown,
            code: code,
            message: "Update intent cannot establish a safe forward transition",
            previous: intent.previous
          )
        end
      end

      sig { params(intent: Intent).returns(T.nilable(String)) }
      def intent_code(intent)
        return "conflicting_intents" if @intents.count { |item| item.previous.key == intent.previous.key } != 1
        return "identity_changed" if intent.previous.name != intent.target.name ||
                                     intent.previous.source != intent.target.source
        return "previous_missing" if @before.packages.none? { |pkg| pkg.key == intent.previous.key }
        return "invalid_target_version" if intent.target.version.empty? || !Version.correct?(intent.target.version)
        return "requested_downgrade" if Version.new(intent.target.version) < Version.new(intent.previous.version)

        nil
      end

      sig { params(intent: Intent).returns(T::Array[Reason]) }
      def transition_reasons(intent)
        incoming = @before.edges.select { |edge| edge.to.key == intent.previous.key }
        selected = incoming.select { |edge| selected?(intent, edge.from) }
        if selected.empty? || missing_parents?(intent, incoming)
          return [Reason.new(
            status: Status::Unknown,
            code: "selection_unproven",
            message: "Every selected parent must have an incoming edge; root updates need manifest evidence",
            previous: intent.previous
          )]
        end

        incoming.map do |edge|
          if selected?(intent, edge.from)
            edge_reason(intent, edge)
          else
            preservation_reason(edge)
          end
        end
      end

      sig { params(intent: Intent, incoming: T::Array[Edge]).returns(T::Boolean) }
      def missing_parents?(intent, incoming)
        parents = intent.parents
        return false unless parents

        parents.any? { |parent| incoming.none? { |edge| edge.from.key == parent.key } }
      end

      sig { params(intent: Intent, parent: Package).returns(T::Boolean) }
      def selected?(intent, parent)
        parents = intent.parents
        parents.nil? || parents.any? { |pkg| pkg.key == parent.key }
      end

      sig { params(parent: Package).returns(T.nilable(Package)) }
      def correlated_parent(parent)
        intent = @intents.find { |item| item.previous.key == parent.key && item.target.key != parent.key }
        retained = @after.packages.find { |pkg| pkg.key == parent.key }
        return retained unless intent
        return nil if retained

        @after.packages.find { |pkg| pkg.key == intent.target.key }
      end

      sig { params(intent: Intent, edge: Edge).returns(Reason) }
      def edge_reason(intent, edge)
        parent = correlated_parent(edge.from)
        return reason(edge, Status::Unknown, "parent_uncorrelated", nil) unless parent

        outgoing = outgoing_edges(parent, edge)
        destination_reason(intent, edge, outgoing)
      end

      sig { params(parent: Package, edge: Edge).returns(T::Array[Edge]) }
      def outgoing_edges(parent, edge)
        @after.edges.select do |item|
          item.from.key == parent.key && item.kind == edge.kind && item.to.name == edge.to.name
        end
      end

      sig { params(intent: Intent, edge: Edge, outgoing: T::Array[Edge]).returns(Reason) }
      def destination_reason(intent, edge, outgoing)
        unchanged = outgoing.find { |item| item.to.key == intent.previous.key }
        return unchanged_reason(intent, edge, outgoing) if unchanged

        target = outgoing.find { |item| item.to.key == intent.target.key }
        if target
          unexpected = novel_destinations(edge, outgoing).reject do |item|
            @intents.any? { |update| update.target.key == item.to.key }
          end
          return reason(edge, Status::Unknown, "ambiguous_destination", nil) unless unexpected.empty?

          return reason(edge, Status::Accepted, "edge_retargeted", target.to)
        end

        alternative_reason(edge, outgoing)
      end

      sig { params(intent: Intent, edge: Edge, outgoing: T::Array[Edge]).returns(Reason) }
      def unchanged_reason(intent, edge, outgoing)
        return reason(edge, Status::Unknown, "unchanged_edge", edge.to) if intent.target.key != intent.previous.key
        return reason(edge, Status::Unknown, "ambiguous_destination", nil) unless
          novel_destinations(edge, outgoing).empty?

        reason(edge, Status::Accepted, "no_op", edge.to)
      end

      sig { params(edge: Edge, outgoing: T::Array[Edge]).returns(T::Array[Edge]) }
      def novel_destinations(edge, outgoing)
        outgoing.reject do |item|
          @before.edges.any? do |prior|
            prior.from.key == edge.from.key && prior.kind == edge.kind && prior.to.key == item.to.key
          end
        end
      end

      sig { params(edge: Edge, outgoing: T::Array[Edge]).returns(Reason) }
      def alternative_reason(edge, outgoing)
        alternatives = novel_destinations(edge, outgoing)
        observed = alternatives.one? ? T.must(alternatives.first).to : nil
        observed ||= T.must(outgoing.first).to if outgoing.one?
        return reason(edge, Status::Unknown, "destination_unproven", nil) unless observed
        return reason(edge, Status::Unknown, "source_changed", observed) if observed.source != edge.to.source

        if Version.new(observed.version) < Version.new(edge.to.version)
          reason(edge, Status::Rejected, "edge_downgrade", observed)
        else
          reason(edge, Status::Unknown, "alternative_version", observed)
        end
      end

      sig { params(edge: Edge).returns(Reason) }
      def preservation_reason(edge)
        parent = correlated_parent(edge.from)
        preserved = parent && @after.edges.any? do |item|
          item.from.key == parent.key && item.to.key == edge.to.key && item.kind == edge.kind
        end
        reason(
          edge,
          preserved ? Status::Accepted : Status::Unknown,
          preserved ? "unselected_edge_preserved" : "unselected_edge_changed",
          preserved ? edge.to : nil
        )
      end

      sig { returns(T::Array[Reason]) }
      def unselected_reasons
        @before.edges.filter_map do |edge|
          related = @intents.any? do |intent|
            intent.previous.name == edge.to.name && intent.previous.source == edge.to.source
          end
          selected_identity = @intents.any? { |intent| intent.previous.key == edge.to.key }
          next unless related && !selected_identity

          preservation_reason(edge)
        end
      end

      sig { params(edge: Edge, status: Status, code: String, observed: T.nilable(Package)).returns(Reason) }
      def reason(edge, status, code, observed)
        Reason.new(
          status: status,
          code: code,
          message: "#{edge.kind} edge: #{code}",
          previous: edge.to,
          parent: edge.from,
          observed: observed
        )
      end
    end
  end
end
