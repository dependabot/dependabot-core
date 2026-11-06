# typed: strict
# frozen_string_literal: true

require "excon"
require "sorbet-runtime"
require "uri"

require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/shared_helpers"

module Dependabot
  # Builds the allowlisted `error-context` hash sent alongside unknown errors so
  # they can be debugged from Sentry without reproducing the job.
  #
  # The context is diagnostic only and must never affect error grouping. It is
  # assembled exclusively from allowlisted keys: raw helper arguments, commands,
  # stderr output and credentials are never forwarded.
  module ErrorReportContext
    extend T::Sig

    Value = T.type_alias { T.any(String, Integer, Float, T::Boolean, T::Array[String]) }
    Context = T.type_alias { T::Hash[String, Value] }

    MAX_STRING_LENGTH = 500
    MAX_ARRAY_LENGTH = 50
    MAX_CAUSE_DEPTH = 5
    REDACTED = "<redacted>"

    # Maps the keys of a HasSentryContext error's `extra` hash that are safe to
    # forward to their `error-context` key. Anything not listed (e.g. a helper's
    # `args`, `command` or `stderr_output`) is dropped.
    SENTRY_EXTRA_KEYS = T.let(
      {
        function: "helper-function",
        process_exit_value: "helper-exit-status",
        process_termsig: "helper-termsig",
        time_taken: "helper-time-taken",
        package_manager: "package-manager-name",
        updated_files: "updated-files",
        dependency_files: "dependency-files"
      }.freeze,
      T::Hash[Symbol, String]
    )

    ATTACHED_CONTEXT_IVAR = :@__dependabot_error_report_context

    # Attaches context to any exception (including third-party ones such as Excon errors)
    # so it can be reported if the exception is not handled. Keys are converted to
    # kebab-case strings and values are normalised; unsupported values are dropped.
    sig { params(error: Exception, context: T::Hash[T.any(String, Symbol), T.anything]).void }
    def self.attach(error, context)
      return if error.frozen?

      merged = attached_context(error).merge(normalize(context))
      error.instance_variable_set(ATTACHED_CONTEXT_IVAR, merged)
    end

    # Returns the context for an error and its causes, or nil when there is
    # nothing to report. Context closer to the reported error takes precedence.
    sig do
      params(
        error: Exception,
        dependency: T.nilable(Dependabot::Dependency)
      ).returns(T.nilable(Context))
    end
    def self.build(error:, dependency: nil)
      context = T.let({}, Context)
      context.merge!(dependency_context(dependency)) if dependency

      error_chain(error).reverse_each { |err| context.merge!(context_for_error(err)) }
      context["cause-class"] = T.must(error.cause).class.name.to_s if error.cause

      context.empty? ? nil : context
    end

    # Returns only the host of a URL: paths can contain private package or
    # organisation names, and some registries embed tokens in them.
    sig { params(url: String).returns(String) }
    def self.host_for(url)
      host = URI.parse(url).host
      host.nil? || host.empty? ? REDACTED : truncate(host)
    rescue URI::Error
      REDACTED
    end

    sig { params(error: Exception).returns(Context) }
    private_class_method def self.context_for_error(error)
      context = T.let({}, Context)
      context.merge!(excon_context(error))
      context.merge!(sentry_extra_context(error))
      if error.is_a?(Dependabot::SharedHelpers::HelperSubprocessFailed)
        context["helper-error-class"] = truncate(error.error_class)
      end
      context.merge!(attached_context(error))
      context
    end

    sig { params(error: Exception).returns(T::Array[Exception]) }
    private_class_method def self.error_chain(error)
      chain = T.let([error], T::Array[Exception])
      while chain.length <= MAX_CAUSE_DEPTH
        cause = T.must(chain.last).cause
        break if cause.nil? || chain.include?(cause)

        chain << cause
      end
      chain
    end

    sig { params(error: Exception).returns(Context) }
    private_class_method def self.attached_context(error)
      value = T.cast(error.instance_variable_get(ATTACHED_CONTEXT_IVAR), T.nilable(Context))
      value || {}
    end

    sig { params(error: Exception).returns(Context) }
    private_class_method def self.sentry_extra_context(error)
      return {} unless error.is_a?(Dependabot::HasSentryContext)

      extra = T.cast(error.sentry_context[:extra], Object)
      return {} unless extra.is_a?(Hash)

      context = T.let({}, Context)
      SENTRY_EXTRA_KEYS.each do |source_key, target_key|
        value = normalize_value(extra[source_key])
        value = strip_pid(value) if source_key == :process_exit_value
        context[target_key] = value unless value.nil?
      end

      names = dependency_names(extra[:dependencies])
      context["dependency-names"] = names if names
      context
    end

    sig { params(error: Exception).returns(Context) }
    private_class_method def self.excon_context(error)
      case error
      when Excon::Error::Socket
        { "socket-error-class" => error.socket_error.class.name.to_s }
      when Excon::Error::HTTPStatus
        http_status_context(error)
      else
        {}
      end
    end

    sig { params(error: Excon::Error::HTTPStatus).returns(Context) }
    private_class_method def self.http_status_context(error)
      context = T.let({}, Context)
      request = T.cast(error.request, Object)
      response = T.cast(error.response, Object)

      if request.is_a?(Hash)
        method = request[:method]
        context["http-method"] = method.to_s.upcase if method
        host = request[:host]
        context["host"] = truncate(host) if host.is_a?(String)
      end
      status = response_status(response)
      context["http-status"] = status if status
      context
    end

    # Excon's own middleware wraps responses in Excon::Response, but status
    # errors can also be built directly from a raw response hash.
    sig { params(response: Object).returns(T.nilable(Integer)) }
    private_class_method def self.response_status(response)
      status = case response
               when Excon::Response then response.status
               when Hash then response[:status]
               end
      status.is_a?(Integer) ? status : nil
    end

    sig { params(dependency: Dependabot::Dependency).returns(Context) }
    private_class_method def self.dependency_context(dependency)
      normalize(
        {
          "dependency-name" => dependency.name,
          "dependency-version" => dependency.version,
          "dependency-previous-version" => dependency.previous_version,
          "dependency-requirement-files" => dependency.requirements.filter_map { |req| req[:file] }.map(&:to_s).uniq
        }
      )
    end

    sig { params(dependencies: T.nilable(Object)).returns(T.nilable(T::Array[String])) }
    private_class_method def self.dependency_names(dependencies)
      return unless dependencies.is_a?(Array)

      names = dependencies.filter_map do |dependency|
        case dependency
        when String then dependency
        when Hash then (dependency["name"] || dependency[:name])&.to_s
        when Dependabot::Dependency then dependency.name
        end
      end
      names.empty? ? nil : names.uniq.first(MAX_ARRAY_LENGTH).map { |name| truncate(name) }
    end

    # `Process::Status#to_s` includes the (meaningless) pid, e.g. "pid 42 exit 1"
    sig { params(value: T.nilable(Value)).returns(T.nilable(Value)) }
    private_class_method def self.strip_pid(value)
      value.is_a?(String) ? value.sub(/\Apid \d+ /, "") : value
    end

    sig { params(context: T::Hash[T.any(String, Symbol), T.anything]).returns(Context) }
    private_class_method def self.normalize(context)
      context.each_with_object(T.let({}, Context)) do |(key, value), normalized|
        normalized_value = normalize_value(T.cast(value, T.nilable(Object)))
        normalized[key.to_s.tr("_", "-")] = normalized_value unless normalized_value.nil?
      end
    end

    sig { params(value: T.nilable(Object)).returns(T.nilable(Value)) }
    private_class_method def self.normalize_value(value)
      case value
      when String then truncate(value)
      when Symbol then truncate(value.to_s)
      when Integer, true, false then value
      # NaN and Infinity can't be serialised to JSON
      when Float then value.finite? ? value : nil
      when Array
        strings = value.select { |item| item.is_a?(String) || item.is_a?(Symbol) }
        strings.empty? ? nil : strings.first(MAX_ARRAY_LENGTH).map { |item| truncate(item.to_s) }
      end
    end

    sig { params(value: String).returns(String) }
    private_class_method def self.truncate(value)
      value.length > MAX_STRING_LENGTH ? "#{value[0, MAX_STRING_LENGTH]}..." : value
    end
  end
end
