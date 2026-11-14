# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/manifest_sets/invalid_catalog"
require "dependabot/manifest_sets/portable_regex"
require "dependabot/manifest_sets/strict_json"

module Dependabot
  module ManifestSets
    # A validated, immutable manifest-set catalog. Build one with `Catalog.parse`; any validation failure
    # rejects the whole document with `InvalidCatalog`.
    class Catalog < T::ImmutableStruct
      extend T::Sig

      SCHEMA_VERSION = 1
      MAX_BYTES = T.let(1024 * 1024, Integer)
      MAX_RULES = 4096
      IDENTIFIER = /\A[a-z0-9][a-z0-9_.-]{0,63}\z/
      DIRECTORY_PARENT = "parent"

      class PathRule < T::ImmutableStruct
        extend T::Sig

        const :id, String
        const :filename_regex, String
        const :directory, String
        const :regex, Regexp

        sig { params(basename: String).returns(T::Boolean) }
        def match?(basename)
          regex.match?(basename)
        end
      end

      class Owner < T::ImmutableStruct
        extend T::Sig

        const :id, String
        const :when_any_basename, T::Array[String], default: []
        const :otherwise, T::Boolean, default: false

        sig { params(basenames: T::Set[String]).returns(T::Boolean) }
        def selected_by?(basenames)
          otherwise || when_any_basename.any? { |name| basenames.include?(name) }
        end
      end

      # The outcome of owner selection: an owner, no owner, or ambiguous (more than one presence owner
      # matched). Ambiguous ownership makes the set unresolvable.
      class OwnerSelection < T::ImmutableStruct
        const :owner, T.nilable(Owner)
        const :ambiguous, T::Boolean
      end

      class Ecosystem < T::ImmutableStruct
        extend T::Sig

        const :id, String
        const :inputs_matched_by_rules, T::Boolean
        const :path_rules, T::Array[PathRule]
        const :owners, T::Array[Owner]

        # IDs of every rule whose regex matches the whole basename, in catalog order.
        sig { params(basename: String).returns(T::Array[String]) }
        def matching_rule_ids(basename)
          path_rules.select { |rule| rule.match?(basename) }.map(&:id)
        end

        sig { params(basename: String).returns(T::Boolean) }
        def rule_matches?(basename)
          path_rules.any? { |rule| rule.match?(basename) }
        end

        # Presence owners are evaluated before the `otherwise` owner. Exactly one matching presence owner
        # wins; more than one is ambiguous and selects nothing. With none, the `otherwise` owner (if any)
        # applies.
        sig { params(basenames: T::Enumerable[String]).returns(OwnerSelection) }
        def select_owner(basenames)
          present = basenames.to_set
          matches = owners.reject(&:otherwise).select { |owner| owner.selected_by?(present) }
          return OwnerSelection.new(owner: nil, ambiguous: true) if matches.length > 1

          OwnerSelection.new(owner: matches.first || owners.find(&:otherwise), ambiguous: false)
        end

        sig { params(owner_id: String).returns(T.nilable(Owner)) }
        def owner(owner_id)
          owners.find { |owner| owner.id == owner_id }
        end

        # Every basename that an owner predicate inspects. Jobs must report these when present.
        sig { returns(T::Array[String]) }
        def selector_basenames
          owners.flat_map(&:when_any_basename).uniq
        end
      end

      const :ecosystems, T::Array[Ecosystem]

      sig { params(id: String).returns(T.nilable(Ecosystem)) }
      def ecosystem(id)
        ecosystems.find { |ecosystem| ecosystem.id == id }
      end

      sig { params(text: String).returns(Catalog) }
      def self.parse(text)
        raise InvalidCatalog.new("catalog_too_large", "catalog exceeds #{MAX_BYTES} bytes") if text.bytesize > MAX_BYTES

        Builder.new(StrictJson.parse(text)).build
      end

      # Converts decoded JSON into typed values, rejecting anything the schema does not allow.
      class Builder
        extend T::Sig

        ROOT_FIELDS = T.let({ "schema_version" => true, "ecosystems" => true }.freeze, T::Hash[String, T::Boolean])
        ECOSYSTEM_FIELDS = T.let(
          { "id" => true, "inputs_matched_by_rules" => false, "path_rules" => true, "owners" => true }.freeze,
          T::Hash[String, T::Boolean]
        )
        RULE_FIELDS = T.let(
          { "id" => true, "filename_regex" => true, "directory" => true }.freeze,
          T::Hash[String, T::Boolean]
        )
        OWNER_FIELDS = T.let(
          { "id" => true, "when_any_basename" => false, "otherwise" => false }.freeze,
          T::Hash[String, T::Boolean]
        )

        sig { params(document: T.anything).void }
        def initialize(document)
          @document = document
          @rule_count = T.let(0, Integer)
        end

        sig { returns(Catalog) }
        def build
          root = object(@document, "catalog", ROOT_FIELDS)
          unless integer(root["schema_version"]) == SCHEMA_VERSION
            invalid("unsupported_schema_version", "schema_version must be #{SCHEMA_VERSION}")
          end

          ecosystems = nonempty_array(root["ecosystems"], "ecosystems").each_with_index.map do |item, index|
            build_ecosystem(item, "ecosystems[#{index}]")
          end
          ensure_unique(ecosystems.map(&:id), "duplicate_ecosystem_id")

          Catalog.new(ecosystems: ecosystems)
        end

        private

        sig { params(item: T.anything, where: String).returns(Ecosystem) }
        def build_ecosystem(item, where)
          hash = object(item, where, ECOSYSTEM_FIELDS)
          id = identifier(hash["id"], "#{where}.id")
          matched = boolean(hash.fetch("inputs_matched_by_rules", false))
          invalid("invalid_type", "#{where}.inputs_matched_by_rules must be a boolean") if matched.nil?

          rules = nonempty_array(hash["path_rules"], "#{where}.path_rules").each_with_index.map do |rule, index|
            build_rule(rule, "#{where}.path_rules[#{index}]")
          end
          ensure_unique(rules.map(&:id), "duplicate_rule_id")

          owners = nonempty_array(hash["owners"], "#{where}.owners").each_with_index.map do |owner, index|
            build_owner(owner, "#{where}.owners[#{index}]")
          end
          ensure_unique(owners.map(&:id), "duplicate_owner_id")
          check_owner_order(owners, where)

          Ecosystem.new(id: id, inputs_matched_by_rules: matched, path_rules: rules, owners: owners)
        end

        sig { params(item: T.anything, where: String).returns(PathRule) }
        def build_rule(item, where)
          @rule_count += 1
          invalid("too_many_rules", "catalog exceeds #{MAX_RULES} rules") if @rule_count > MAX_RULES

          hash = object(item, where, RULE_FIELDS)
          id = identifier(hash["id"], "#{where}.id")
          source = string(hash["filename_regex"], "#{where}.filename_regex")
          directory = string(hash["directory"], "#{where}.directory")
          unless directory == DIRECTORY_PARENT
            invalid("invalid_directory", "#{where}.directory must be #{DIRECTORY_PARENT.inspect}")
          end

          PathRule.new(
            id: id,
            filename_regex: source,
            directory: directory,
            regex: PortableRegex.compile(id, source)
          )
        end

        sig { params(item: T.anything, where: String).returns(Owner) }
        def build_owner(item, where)
          hash = object(item, where, OWNER_FIELDS)
          id = identifier(hash["id"], "#{where}.id")
          has_names = hash.key?("when_any_basename")
          has_otherwise = hash.key?("otherwise")
          if has_names == has_otherwise
            invalid("invalid_type", "#{where} needs exactly one of when_any_basename or otherwise")
          end
          return Owner.new(id: id, when_any_basename: basenames(hash["when_any_basename"], where)) if has_names

          invalid("invalid_type", "#{where}.otherwise must be true") unless boolean(hash["otherwise"]) == true
          Owner.new(id: id, otherwise: true)
        end

        sig { params(value: T.anything, where: String).returns(T::Array[String]) }
        def basenames(value, where)
          names = nonempty_array(value, "#{where}.when_any_basename").map do |name|
            name = string(name, "#{where}.when_any_basename")
            if name.empty? || name.include?("/") || name.include?("\0")
              invalid("invalid_type", "#{where}.when_any_basename entries must be basenames")
            end
            name
          end
          invalid("invalid_type", "#{where}.when_any_basename has duplicates") unless names.uniq.length == names.length
          names
        end

        sig { params(owners: T::Array[Owner], where: String).void }
        def check_owner_order(owners, where)
          fallback_index = owners.index(&:otherwise)
          return if fallback_index.nil? || fallback_index == owners.length - 1

          invalid("invalid_owner_order", "#{where}.owners: the otherwise owner must be last and unique")
        end

        sig do
          params(value: T.anything, where: String, fields: T::Hash[String, T::Boolean])
            .returns(T::Hash[String, T.anything])
        end
        def object(value, where, fields)
          hash = case value
                 when Hash then T.let(value, T::Hash[String, T.anything])
                 else invalid("invalid_type", "#{where} must be an object")
                 end
          unknown = hash.keys - fields.keys
          invalid("unknown_field", "#{where} has unknown field(s) #{unknown.join(', ')}") if unknown.any?
          fields.each do |name, required|
            invalid("missing_field", "#{where}.#{name} is required") if required && !hash.key?(name)
          end
          hash
        end

        sig { params(value: T.anything, where: String).returns(T::Array[T.anything]) }
        def nonempty_array(value, where)
          case value
          when Array
            return value if value.any?
          end
          invalid("invalid_type", "#{where} must be a non-empty array")
        end

        sig { params(value: T.anything, where: String).returns(String) }
        def string(value, where)
          case value
          when String then value
          else invalid("invalid_type", "#{where} must be a string")
          end
        end

        sig { params(value: T.anything, where: String).returns(String) }
        def identifier(value, where)
          id = string(value, where)
          invalid("invalid_identifier", "#{where} #{id.inspect} is not a valid identifier") unless IDENTIFIER.match?(id)
          id
        end

        sig { params(value: T.anything).returns(T.nilable(T::Boolean)) }
        def boolean(value)
          case value
          when TrueClass, FalseClass then value
          end
        end

        # JSON integers only; 1.0 and "1" are not integers.
        sig { params(value: T.anything).returns(T.nilable(Integer)) }
        def integer(value)
          case value
          when Integer then value
          end
        end

        sig { params(ids: T::Array[String], code: String).void }
        def ensure_unique(ids, code)
          duplicate = ids.find { |id| ids.count(id) > 1 }
          invalid(code, "#{duplicate.inspect} appears more than once") if duplicate
        end

        sig { params(code: String, message: String).returns(T.noreturn) }
        def invalid(code, message)
          raise InvalidCatalog.new(code, message)
        end
      end
    end
  end
end
