# typed: strict
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Shared
      class PackageManagerDetector
        extend T::Sig
        extend T::Helpers

        sig do
          params(
            lockfiles: T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)],
            package_json: T.nilable(T::Hash[String, T.untyped])
          ).void
        end
        def initialize(lockfiles, package_json)
          @lockfiles = lockfiles
          @package_json = package_json
          @manifest_package_manager = T.let(package_json&.fetch(MANIFEST_PACKAGE_MANAGER_KEY, nil), T.nilable(String))
          @engines = T.let(package_json&.fetch(MANIFEST_ENGINES_KEY, {}), T::Hash[String, T.untyped])
        end

        # Returns npm, yarn, or pnpm based on the lockfiles, package.json, and engines
        # Defaults to npm if no package manager is detected
        sig { returns(String) }
        def detect_package_manager
          package_manager = name_from_lockfiles ||
                            name_from_package_manager_attr ||
                            name_from_engines

          if package_manager
            Dependabot.logger.info("Detected package manager: #{package_manager}")
          else
            package_manager = DEFAULT_PACKAGE_MANAGER
            Dependabot.logger.info("Default package manager used: #{package_manager}")
          end
          package_manager
        rescue StandardError => e
          Dependabot.logger.error("Error detecting package manager: #{e.message}")
          DEFAULT_PACKAGE_MANAGER
        end

        private

        sig { returns(T.nilable(String)) }
        def name_from_lockfiles
          PACKAGE_MANAGER_CLASSES.keys.map(&:to_s).find { |manager_name| @lockfiles[manager_name.to_sym] }
        end

        sig { returns(T.nilable(String)) }
        def name_from_package_manager_attr
          return unless @manifest_package_manager

          PACKAGE_MANAGER_CLASSES.keys.map(&:to_s).find do |manager_name|
            @manifest_package_manager.start_with?("#{manager_name}@")
          end
        end

        sig { returns(T.nilable(String)) }
        def name_from_engines
          return unless @engines.is_a?(Hash)

          PACKAGE_MANAGER_CLASSES.each_key do |manager_name|
            return manager_name if @engines[manager_name]
          end
          nil
        end
      end
    end
  end
end
