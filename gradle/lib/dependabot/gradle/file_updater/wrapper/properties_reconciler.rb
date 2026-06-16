# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/file_updater"
require "dependabot/gradle/file_updater/wrapper/properties_document"

module Dependabot
  module Gradle
    class FileUpdater
      module Wrapper
        # Reconciles the `gradle-wrapper.properties` file after Gradle's wrapper task has
        # regenerated it from hardcoded defaults (see https://github.com/gradle/gradle/issues/36172).
        #
        # The reconciliation policy is deliberately conservative: the user's original file is the
        # source of truth for everything (comments, ordering, custom keys, networkTimeout, retries,
        # retryBackOffMs, validateDistributionUrl, distributionBase/Path, store paths, ...). Only the
        # keys that legitimately change for a version bump are taken from the regenerated file.
        class PropertiesReconciler
          extend T::Sig

          # Keys whose value is owned by the update itself and therefore taken from the regenerated
          # file. Everything not listed here is preserved verbatim from the user's original file.
          MANAGED_KEYS = T.let(
            %w(distributionUrl distributionSha256Sum).freeze,
            T::Array[String]
          )

          # Returns the reconciled properties content, or the original content when either side is
          # missing (e.g. the wrapper task did not produce a properties file).
          sig do
            params(original_content: T.nilable(String), regenerated_content: T.nilable(String))
              .returns(T.nilable(String))
          end
          def self.reconcile(original_content:, regenerated_content:)
            new(original_content: original_content, regenerated_content: regenerated_content).reconcile
          end

          sig { params(original_content: T.nilable(String), regenerated_content: T.nilable(String)).void }
          def initialize(original_content:, regenerated_content:)
            @original_content = original_content
            @regenerated_content = regenerated_content
          end

          sig { returns(T.nilable(String)) }
          def reconcile
            original_content = @original_content
            regenerated_content = @regenerated_content
            return original_content if original_content.nil? || regenerated_content.nil?

            document = PropertiesDocument.parse(original_content)
            regenerated = PropertiesDocument.parse(regenerated_content)

            MANAGED_KEYS.each do |key|
              new_value = regenerated.value_for(key)
              next if new_value.nil?

              document.upsert(key, new_value)
            end

            document.to_s
          end
        end
      end
    end
  end
end
