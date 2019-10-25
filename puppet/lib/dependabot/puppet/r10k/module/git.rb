# frozen_string_literal: true

module Dependabot
  module Puppet
    module Puppetfile
      module R10K
        module Module
          class Git < Dependabot::Puppet::Puppetfile::R10K::Module::Base
            def self.implements?(_name, args)
              args.is_a?(Hash) && args.key?(:git)
            rescue StandardError
              false
            end

            def properties
              {
                :type => :git
              }
            end
          end
        end
      end
    end
  end
end
