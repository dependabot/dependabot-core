# frozen_string_literal: true

module Dependabot
  module Puppet
    module Puppetfile
      module R10K
        module Module
          class Invalid < Dependabot::Puppet::Puppetfile::R10K::Module::Base
            def self.implements?(_name, _args)
              true
            end

            def initialize(title, args)
              super
              @error_message = format("Module %<title>s with args %<args>s doesn't have an implementation. (Are you using the right arguments?)", title: title, args: args.inspect)
            end

            def properties
              {
                :type          => :invalid,
                :error_message => @error_message
              }
            end
          end
        end
      end
    end
  end
end
