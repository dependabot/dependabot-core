# frozen_string_literal: true

require 'uri'

module Dependabot
  module Swift
    module Package
      class Identifier
        include Comparable

        SCOPE_REGEX = /[a-zA-Z\d](?:[a-zA-Z\d]|-(?=[a-zA-Z\d])){0,38}/
        NAME_REGEX = /\p{XID_Start}\p{XID_Continue}{0,127}/

        attr_reader :scope, :name

        def initialize(string)
          case string
          when %r{\Ahttps?://(?:www\.)?github.com(?:\:\d+)?/#{SCOPE_REGEX}/#{NAME_REGEX}(?:\.git)?\z}
            components = URI(string).path.split("/").reject(&:empty?)
            @scope = components.first
            @name = components.last.sub(/\.git$/, "")
          when %r{\A(?:ssh\://)?git@github.com[/:]#{SCOPE_REGEX}/#{NAME_REGEX}(?:\.git)?\z}
            components = string.sub(%r{(?:ssh\://)?git@github.com[:/]}, "").split("/")
            @scope = components.first
            @name = components.last.sub(/\.git$/, "")
          when %r{\A#{SCOPE_REGEX}\.#{NAME_REGEX}\z}
            @scope, @name = string.split(".")
          else
            return
          end
        end

        def normalized
          "#{@scope.downcase}.#{@name.unicode_normalize(:nfkc).downcase(:fold)}"
        end

        def inspect
          "#<#{self.class.name}:#{self.object_id} scope: #{@scope}, name: #{@name}>"
        end

        def to_s
          "#{scope}.#{name}"
        end

        def <=>(other)
          self.normalized <=> other.normalized
        end
      end
    end
  end
end
