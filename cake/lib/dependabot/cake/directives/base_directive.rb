# frozen_string_literal: true

require_relative "directives"

module Dependabot
  module Cake
    module Directives
      class BaseDirective
        SCHEME    = /(?<scheme>[^:]{2,}:)/i.freeze
        URL       = /(?<url>[^?]+)?/.freeze
        QUERY     = /[?](?<query>.*)/.freeze
        CONTEXT   = /#{SCHEME}#{URL}#{QUERY}/.freeze

        def initialize(line)
          line = "#{default_scheme}:?path=#{line}" if line !~ SCHEME

          parsed_from_line = CONTEXT.match(line).named_captures
          @scheme = parsed_from_line.fetch("scheme").chomp(":")
          @url = parsed_from_line.fetch("url")
          @query = query_string_to_hash(parsed_from_line.fetch("query"))
        end

        def to_h
          {
            type: @type,
            scheme: @scheme,
            url: @url,
            query: @query
          }
        end

        attr_reader :type, :scheme, :url, :query

        private

        def default_scheme
          raise NotImplementedError
        end

        def query_string_to_hash(query_string)
          query_params = {}

          # skip empty params
          query_string&.split("&")&.each do |param|
            next if param.empty?

            name, value = param.split("=")
            value ||= true

            query_params[name.downcase.to_sym] = value
          end
          query_params
        end
      end
    end
  end
end
