# frozen_string_literal: true

module Dependabot
  module Utils
    module Go
      module SharedHelper
        def self.path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          platform =
            case RbConfig::CONFIG["arch"]
            when /linux/ then "linux"
            when /darwin/ then "darwin"
            else raise "Invalid platform #{RbConfig::CONFIG['arch']}"
            end
          File.join(project_root, "helpers/go/go-helpers.#{platform}64")
        end
      end
    end
  end
end
