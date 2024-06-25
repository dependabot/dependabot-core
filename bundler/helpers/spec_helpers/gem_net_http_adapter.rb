# typed: false
# frozen_string_literal: true

require "rubygems/vendored_net_http"

module WebMock
  module HttpLibAdapters
    class GemNetHttpAdapter < HttpLibAdapter
      adapter_for :gem_net_http

      OriginalGemNetHTTP = ::Gem::Net::HTTP unless const_defined?(:OriginalGemNetHTTP)

      def self.enable!
        ::Gem::Net.send(:remove_const, :HTTP)
        ::Gem::Net.send(:remove_const, :HTTPSession)
        ::Gem::Net.send(:const_set, :HTTP, @webMockNetHTTP)
        ::Gem::Net.send(:const_set, :HTTPSession, @webMockNetHTTP)
      end

      def self.disable!
        ::Gem::Net.send(:remove_const, :HTTP)
        ::Gem::Net.send(:remove_const, :HTTPSession)
        ::Gem::Net.send(:const_set, :HTTP, OriginalGemNetHTTP)
        ::Gem::Net.send(:const_set, :HTTPSession, OriginalGemNetHTTP)

        # copy all constants from @webMockNetHTTP to original Net::HTTP
        # in case any constants were added to @webMockNetHTTP instead of Net::HTTP
        # after WebMock was enabled.
        # i.e Net::HTTP::DigestAuth
        @webMockNetHTTP.constants.each do |constant|
          unless OriginalGemNetHTTP.constants.map(&:to_s).include?(constant.to_s)
            OriginalGemNetHTTP.send(:const_set, constant, @webMockNetHTTP.const_get(constant))
          end
        end
      end

      @webMockNetHTTP = Class.new(::Gem::Net::HTTP) do
        class << self
          def socket_type
            StubSocket
          end

          if Module.method(:const_defined?).arity == 1
            def const_defined?(name)
              super || superclass.const_defined?(name)
            end
          else
            def const_defined?(name, inherit = true)
              super || superclass.const_defined?(name, inherit)
            end
          end

          if Module.method(:const_get).arity != 1
            def const_get(name, inherit = true)
              super
            rescue NameError
              superclass.const_get(name, inherit)
            end
          end

          if Module.method(:constants).arity != 0
            def constants(inherit = true)
              (super + superclass.constants(inherit)).uniq
            end
          end
        end

        def request(request, body = nil, &block)
          request_signature = WebMock::NetHTTPUtility.request_signature_from_request(self, request, body)

          WebMock::RequestRegistry.instance.requested_signatures.put(request_signature)

          if webmock_response = WebMock::StubRegistry.instance.response_for_request(request_signature)
            @socket = ::Gem::Net::HTTP.socket_type.new
            WebMock::CallbackRegistry.invoke_callbacks(
              { lib: :net_http }, request_signature, webmock_response
            )
            build_net_http_response(webmock_response, request.uri, &block)
          elsif WebMock.net_connect_allowed?(request_signature.uri)
            check_right_http_connection
            after_request = lambda do |response|
              if WebMock::CallbackRegistry.any_callbacks?
                webmock_response = build_webmock_response(response)
                WebMock::CallbackRegistry.invoke_callbacks(
                  { lib: :net_http, real_request: true }, request_signature, webmock_response
                )
              end
              response.extend Net::WebMockHTTPResponse
              yield response if block
              response
            end
            super_with_after_request = lambda {
              response = super(request, nil, &nil)
              after_request.call(response)
            }
            if started?
              ensure_actual_connection
              super_with_after_request.call
            else
              start_with_connect do
                super_with_after_request.call
              end
            end
          else
            raise WebMock::NetConnectNotAllowedError.new(request_signature)
          end
        end

        def start_without_connect
          raise IOError, "HTTP session already opened" if @started

          if block_given?
            begin
              @socket = ::Gem::Net::HTTP.socket_type.new
              @started = true
              return yield(self)
            ensure
              do_finish
            end
          end
          @socket = ::Gem::Net::HTTP.socket_type.new
          @started = true
          self
        end

        def ensure_actual_connection
          return unless @socket.is_a?(StubSocket)

          @socket&.close
          @socket = nil
          do_start
        end

        alias_method :start_with_connect, :start

        def start(&block)
          uri = Addressable::URI.parse(WebMock::NetHTTPUtility.get_uri(self))

          if WebMock.net_http_connect_on_start?(uri)
            super(&block)
          else
            start_without_connect(&block)
          end
        end

        def build_net_http_response(webmock_response, request_uri)
          response = ::Gem::Net::HTTPResponse.send(:response_class, webmock_response.status[0].to_s).new("1.0",
                                                                                                         webmock_response.status[0].to_s, webmock_response.status[1])
          body = webmock_response.body
          body = nil if webmock_response.status[0].to_s == "204"

          response.instance_variable_set(:@body, body)
          webmock_response.headers.to_a.each do |name, values|
            values = [values] unless values.is_a?(Array)
            values.each do |value|
              response.add_field(name, value)
            end
          end

          response.instance_variable_set(:@read, true)

          response.uri = request_uri

          response.extend Net::WebMockHTTPResponse

          raise Net::OpenTimeout, "execution expired" if webmock_response.should_timeout

          webmock_response.raise_error_if_any

          yield response if block_given?

          response
        end

        def build_webmock_response(net_http_response)
          webmock_response = WebMock::Response.new
          webmock_response.status = [
            net_http_response.code.to_i,
            net_http_response.message
          ]
          webmock_response.headers = net_http_response.to_hash
          webmock_response.body = net_http_response.body
          webmock_response
        end

        def check_right_http_connection
          return if @@alredy_checked_for_right_http_connection ||= false

          WebMock::NetHTTPUtility.puts_warning_for_right_http_if_needed
          @@alredy_checked_for_right_http_connection = true
        end
      end
      @webMockNetHTTP.version_1_2
      [
        [:Get, ::Gem::Net::HTTP::Get],
        [:Post, ::Gem::Net::HTTP::Post],
        [:Put, ::Gem::Net::HTTP::Put],
        [:Delete, ::Gem::Net::HTTP::Delete],
        [:Head, ::Gem::Net::HTTP::Head],
        [:Options, ::Gem::Net::HTTP::Options]
      ].each do |c|
        @webMockNetHTTP.const_set(c[0], c[1])
      end
    end
  end

  class StubSocket # :nodoc:
    attr_accessor :read_timeout
    attr_accessor :continue_timeout
    attr_accessor :write_timeout

    def initialize(*_args)
      @closed = false
    end

    def closed?
      @closed
    end

    def close
      @closed = true
      nil
    end

    def readuntil(*args); end

    def io
      @io ||= StubIO.new
    end

    class StubIO
      def setsockopt(*args); end
      def peer_cert; end
      def peeraddr = ["AF_INET", 443, "127.0.0.1", "127.0.0.1"]
      def ssl_version = "TLSv1.3"
      def cipher = ["TLS_AES_128_GCM_SHA256", "TLSv1.3", 128, 128]
    end
  end
end
