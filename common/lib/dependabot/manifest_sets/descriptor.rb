# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/manifest_sets/inputs"

module Dependabot
  module ManifestSets
    # What one job reports about the manifest set in its directory: the set's original repository inputs
    # (`present`), proof that the set no longer exists (`absent`), or an explicit reason why its inputs
    # cannot be listed (`unresolvable`). A job that can say none of these reports no descriptor at all.
    class Descriptor < T::ImmutableStruct
      extend T::Sig

      SCHEMA_VERSION = 1

      class State < T::Enum
        enums do
          Present = new("present")
          Absent = new("absent")
          Unresolvable = new("unresolvable")
        end
      end

      # The input list exceeds a descriptor limit. The list is never truncated.
      INPUT_LIMIT = "input_limit"
      # A go.work file makes the module read files beyond its own go.mod.
      WORKSPACE = "workspace"
      # A relative replace directive points at a module elsewhere in the repository.
      LOCAL_REPLACE = "local_replace"
      # More than one owner's selector is present, so the set has no single owner.
      AMBIGUOUS_OWNER = "ambiguous_owner"
      UNKNOWN_PROVENANCE = Inputs::UNKNOWN_PROVENANCE

      MAX_FILES = 4096
      MAX_PATH_BYTES = 4096
      MAX_ENCODED_BYTES = T.let(1024 * 1024, Integer)

      const :ecosystem, String
      # Canonical set directory: "." for the root, otherwise repository-relative with no surrounding slashes.
      const :directory, String
      const :owner, String
      const :graph_version, String
      const :state, State
      const :files, T::Array[InputFile], default: []
      const :reason, T.nilable(String), default: nil

      sig do
        params(
          ecosystem: String,
          directory: String,
          owner: String,
          graph_version: String,
          files: T::Array[InputFile]
        ).returns(Descriptor)
      end
      def self.present(ecosystem:, directory:, owner:, graph_version:, files:)
        raise ArgumentError, "a present manifest set needs at least one input" if files.empty?

        descriptor = new(ecosystem:, directory:, owner:, graph_version:, state: State::Present, files:)
        return descriptor if descriptor.within_limits?

        unresolvable(ecosystem:, directory:, owner:, graph_version:, reason: INPUT_LIMIT)
      end

      sig { params(ecosystem: String, directory: String, owner: String, graph_version: String).returns(Descriptor) }
      def self.absent(ecosystem:, directory:, owner:, graph_version:)
        new(ecosystem:, directory:, owner:, graph_version:, state: State::Absent)
      end

      sig do
        params(
          ecosystem: String,
          directory: String,
          owner: String,
          graph_version: String,
          reason: String
        ).returns(Descriptor)
      end
      def self.unresolvable(ecosystem:, directory:, owner:, graph_version:, reason:)
        new(ecosystem:, directory:, owner:, graph_version:, state: State::Unresolvable, reason:)
      end

      # The decoded envelope. `files` is omitted for an unresolvable set and present (possibly empty) otherwise;
      # `reason` appears only for an unresolvable set.
      sig { returns(T::Hash[String, Object]) }
      def to_h
        envelope = T.let(
          {
            "schema_version" => SCHEMA_VERSION,
            "ecosystem" => ecosystem,
            "directory" => directory,
            "owner" => owner,
            "graph_version" => graph_version,
            "state" => state.serialize
          },
          T::Hash[String, Object]
        )
        if state == State::Unresolvable
          envelope["reason"] = reason
        else
          envelope["files"] = files.map { |file| { "path" => file.path, "blob_oid" => file.blob_oid } }
        end
        envelope
      end

      sig { returns(String) }
      def to_json_string
        JSON.generate(to_h)
      end

      sig { returns(T::Boolean) }
      def within_limits?
        return false if files.length > MAX_FILES
        return false if files.any? { |file| file.path.bytesize > MAX_PATH_BYTES }

        to_json_string.bytesize <= MAX_ENCODED_BYTES
      end
    end
  end
end
