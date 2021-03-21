# frozen_string_literal: true

require "dependabot/pull_request_creator/labeler"

module Dependabot
  class PullRequestCreator
    module Labelers
      class Azure < Labeler
        @package_manager_labels = {}

        # Azure does not have centralised labels
        def labels
          @labels ||= [
            DEFAULT_DEPENDENCIES_LABEL,
            DEFAULT_SECURITY_LABEL,
            language_name
          ]
        end

        def create_dependencies_label
          labels
        end

        def create_security_label
          labels
        end

        def create_language_label
          labels
        end
      end
    end
  end
end
