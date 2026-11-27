# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/file_updaters/base"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      # SwiftPM evaluates package manifests on the host that resolves them. A manifest that adds a dependency under
      # `#if os(Linux)` or `#if !canImport(Combine)` therefore makes the updater's Linux image pin a package that
      # builds for Apple platforms never use. The pins that SwiftPM adds when it resolves the unchanged project are
      # such host-only pins, unless the committed Package.resolved already has them.
      class HostOnlyPins
        extend T::Sig

        sig { params(committed: String, resolved_on_host: String).void }
        def initialize(committed:, resolved_on_host:)
          @keys = T.let(pin_keys(resolved_on_host) - pin_keys(committed), T::Array[String])
        end

        # The pins' locations (or identities, for pins without one).
        sig { returns(T::Array[String]) }
        attr_reader :keys

        # Leaves the host-only pins out of a Package.resolved that SwiftPM wrote, keeping its formatting.
        # Returns the content unchanged when there is nothing to leave out.
        sig { params(content: String).returns(String) }
        def remove_from(content)
          return content if keys.empty?

          data = parse(content)
          pins = data && data["pins"]
          return content unless data && pins.is_a?(Array)

          kept = pins.reject { |pin| pin.is_a?(Hash) && keys.include?(pin_key(pin)) }
          return content if kept.length == pins.length

          data["pins"] = kept
          "#{JSON.pretty_generate(data, space_before: ' ')}\n"
        end

        private

        sig { params(content: String).returns(T::Array[String]) }
        def pin_keys(content)
          data = parse(content)
          return [] unless data

          # Version 1 of the format nests the pins under "object".
          container = data.key?("object") ? data["object"] : data
          pins = container.is_a?(Hash) ? container["pins"] : nil
          return [] unless pins.is_a?(Array)

          pins.filter_map { |pin| pin_key(pin) if pin.is_a?(Hash) }
        end

        sig { params(pin: T::Hash[String, Object]).returns(T.nilable(String)) }
        def pin_key(pin)
          location = pin["location"] || pin["repositoryURL"]
          if location.is_a?(String) && !location.empty?
            return location.downcase.delete_suffix("/").delete_suffix(".git")
          end

          identity = pin["identity"]
          identity.is_a?(String) ? identity.downcase : nil
        end

        sig { params(content: String).returns(T.nilable(T::Hash[String, Object])) }
        def parse(content)
          data = JSON.parse(content)
          data.is_a?(Hash) ? data : nil
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
