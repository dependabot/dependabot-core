# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/powershell/file_parser"

module Dependabot
  module Powershell
    class FileParser < Dependabot::FileParsers::Base
      # Parses individual PowerShell module specification entries. An entry is
      # either a bare quoted module name/path (e.g. `'Az.Storage'`) or an
      # `@{ ModuleName = ...; ... }` hashtable literal specifying a module
      # name plus optional GUID and version constraints. Also provides the
      # shared helper for splitting comma/newline separated lists of such
      # entries while respecting nested braces, parens and quoted strings.
      class ModuleSpecificationParser
        extend T::Sig

        # Bare-string entries that look like filesystem paths (relative,
        # absolute, drive-rooted, or referencing a module file directly)
        # point at a module outside the PowerShell Gallery and cannot be
        # resolved as a registry dependency.
        PATH_INDICATORS = T.let(
          %r{\A(\.{1,2}[\\/]|[\\/]|[A-Za-z]:[\\/]|~[\\/])|\.(psd1|psm1|ps1)\z}i,
          Regexp
        )

        # Splits a comma-separated list of entries at the top level, ignoring
        # commas that appear inside quoted strings or nested `@{...}` /
        # `@(...)` literals.
        sig { params(text: String).returns(T::Array[String]) }
        def self.split_entries(text)
          split_on(text, ",")
        end

        # Splits `text` on the top-level occurrences of `separator`, ignoring
        # occurrences that appear inside quoted strings or nested `@{...}` /
        # `@(...)` literals. Used both to split a list of module entries
        # (separator `,`) and the `Key = Value` pairs within a hashtable
        # literal's body (separator `;`).
        sig { params(text: String, separator: String).returns(T::Array[String]) }
        def self.split_on(text, separator)
          entries = []
          buffer = +""
          depth = 0
          quote = T.let(nil, T.nilable(String))

          text.each_char do |char|
            if quote
              buffer << char
              quote = nil if char == quote
              next
            end

            case char
            when "'", "\""
              quote = char
              buffer << char
            when "{", "("
              depth += 1
              buffer << char
            when "}", ")"
              depth -= 1
              buffer << char
            when separator
              if depth.zero?
                entries << buffer
                buffer = +""
              else
                buffer << char
              end
            else
              buffer << char
            end
          end
          entries << buffer

          entries.map(&:strip).reject(&:empty?)
        end

        # Parses a single entry string into a ModuleDeclaration, or nil if the
        # entry is path-based (not resolvable via the PowerShell Gallery) or
        # otherwise invalid (e.g. conflicting version keys).
        sig { params(entry: String, declaration_type: Symbol).returns(T.nilable(ModuleDeclaration)) }
        def self.parse(entry, declaration_type:)
          entry = entry.strip
          return nil if entry.empty?

          if entry.start_with?("@{")
            parse_hashtable(entry, declaration_type: declaration_type)
          else
            parse_bare_name(entry, declaration_type: declaration_type)
          end
        end

        sig { params(entry: String, declaration_type: Symbol).returns(T.nilable(ModuleDeclaration)) }
        def self.parse_bare_name(entry, declaration_type:)
          name = unquote(entry)
          return nil if name.empty? || path_based?(name)

          ModuleDeclaration.new(
            name: name,
            metadata: { declaration_type: declaration_type, style: :string }
          )
        end

        sig { params(entry: String, declaration_type: Symbol).returns(T.nilable(ModuleDeclaration)) }
        def self.parse_hashtable(entry, declaration_type:)
          fields = hashtable_fields(entry)
          name = fields["ModuleName"]
          return nil if name.nil? || name.empty? || path_based?(name)

          module_version = fields["ModuleVersion"]
          maximum_version = fields["MaximumVersion"]
          required_version = fields["RequiredVersion"]

          # RequiredVersion is an exact pin and is invalid when combined with
          # a minimum/maximum range in the same module specification.
          return nil if required_version && (module_version || maximum_version)

          requirement, version = build_requirement(module_version, maximum_version, required_version)

          ModuleDeclaration.new(
            name: name,
            version: version,
            requirement: requirement,
            metadata: {
              declaration_type: declaration_type,
              style: :hashtable,
              guid: fields["GUID"],
              version_key: version_key(module_version, maximum_version, required_version)
            }
          )
        end

        # Extracts the `Key = Value` pairs from the body of an `@{...}`
        # hashtable literal into a Hash keyed by the (case-sensitive) key
        # name, with quoted values unwrapped.
        sig { params(entry: String).returns(T::Hash[String, String]) }
        def self.hashtable_fields(entry)
          body = entry.delete_prefix("@{").delete_suffix("}").gsub(/[\r\n]+/, ";")

          split_on(body, ";").each_with_object({}) do |pair, fields|
            key, value = pair.split("=", 2)
            next unless key && value

            fields[key.strip] = unquote(value.strip)
          end
        end

        sig do
          params(
            module_version: T.nilable(String),
            maximum_version: T.nilable(String),
            required_version: T.nilable(String)
          ).returns([T.nilable(String), T.nilable(String)])
        end
        def self.build_requirement(module_version, maximum_version, required_version)
          return ["= #{required_version}", required_version] if required_version

          constraints = []
          constraints << ">= #{module_version}" if module_version
          constraints << "<= #{maximum_version}" if maximum_version

          [constraints.empty? ? nil : constraints.join(", "), nil]
        end

        sig do
          params(
            module_version: T.nilable(String),
            maximum_version: T.nilable(String),
            required_version: T.nilable(String)
          ).returns(T.nilable(String))
        end
        def self.version_key(module_version, maximum_version, required_version)
          return "RequiredVersion" if required_version
          return "ModuleVersion+MaximumVersion" if module_version && maximum_version
          return "ModuleVersion" if module_version

          "MaximumVersion" if maximum_version
        end

        sig { params(value: String).returns(String) }
        def self.unquote(value)
          value = value.strip
          if (value.start_with?("'") && value.end_with?("'") && value.length >= 2) ||
             (value.start_with?("\"") && value.end_with?("\"") && value.length >= 2)
            value[1..-2].to_s
          else
            value
          end
        end

        sig { params(name: String).returns(T::Boolean) }
        def self.path_based?(name)
          !!(name =~ PATH_INDICATORS)
        end
      end
    end
  end
end
