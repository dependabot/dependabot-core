# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "base"

module Dependabot
  class PullRequestCreator
    class MessageBuilder
      module Strategies
        # Generates base title for single dependency updates
        class SingleUpdate < Base
          sig do
            params(
              dependency: Dependency,
              library: T::Boolean,
              directory: T.nilable(String)
            ).void
          end
          def initialize(dependency:, library: false, directory: nil)
            @dependency = dependency
            @library = library
            @directory = directory
          end

          sig { override.returns(String) }
          def base_title
            title = if @library
                      "update #{@dependency.display_name} requirement " \
                        "from #{@dependency.previous_version} to #{@dependency.version}"
                    else
                      "bump #{@dependency.display_name} " \
                        "from #{@dependency.humanized_previous_version} to #{@dependency.humanized_version}"
                    end
            "#{title}#{directory_suffix}"
          end

          private

          sig { returns(String) }
          def directory_suffix
            return "" unless @directory && @directory != "/"

            " in #{@directory}"
          end
        end
      end
    end
  end
end