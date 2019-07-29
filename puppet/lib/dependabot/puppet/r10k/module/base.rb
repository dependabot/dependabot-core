# frozen_string_literal: true

module Dependabot
  module Puppet
    module Puppetfile
      module R10K
        module Module
          def self.from_puppetfile(title, args)
            return Git.new(title, args) if Git.implements?(title, args)
            return Svn.new(title, args) if Svn.implements?(title, args)
            return Local.new(title, args) if Local.implements?(title, args)
            return Forge.new(title, args) if Forge.implements?(title, args)

            Invalid.new(title, args)
          end

          class Base
            # The full title of the module
            attr_reader :title

            # The name of the module
            attr_reader :name

            # The line number where this module is first found in Puppetfile
            attr_reader :puppetfile_line_number

            def initialize(title, args)
              @title = title
              @args = args
              @owner, @name = parse_title(@title)

              @puppetfile_line_number = find_load_location
            end

            # Should be overridden in concrete module classes
            def version
              nil
            end

            # Should be overridden in concrete module classes
            def properties
              {}
            end

            private

            def parse_title(title)
              if (match = title.match(/\A(\w+)\Z/))
                [nil, match[1]]
              elsif (match = title.match(/\A(\w+)[-\/](\w+)\Z/))
                [match[1], match[2]]
              else
                raise ArgumentError, format("Module name (%<title>s) must match either 'modulename' or 'owner/modulename'", title: title)
              end
            end

            def find_load_location
              loc = Kernel.caller_locations
                          .find { |call_loc| call_loc.absolute_path == Dependabot::Puppet::Puppetfile::R10K::PUPPETFILE_MONIKER }
              loc.nil? ? 0 : loc.lineno - 1 # Line numbers from ruby are base 1
            end
          end
        end
      end
    end
  end
end
