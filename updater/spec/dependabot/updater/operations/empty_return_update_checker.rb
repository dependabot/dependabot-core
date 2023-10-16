# typed: true
# frozen_string_literal: true

module Dependabot
  module EmptyReturn
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      def can_update?(_requirements_to_unlock)
        true
      end

      def updated_dependencies(_requirements_to_unlock)
        []
      end

      def latest_version
        1
      end

      def up_to_date?
        false
      end
    end
  end
end

Dependabot::UpdateCheckers.register("emptyreturn", Dependabot::EmptyReturn::UpdateChecker)

module Dependabot
  module EmptyReturn
    class FileParser < Dependabot::FileParsers::Base
      def check_required_files; end

      def parse
        []
      end
    end
  end
end

Dependabot::FileParsers.register("emptyreturn", Dependabot::EmptyReturn::FileParser)
