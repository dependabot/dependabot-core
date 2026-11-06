# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "uri"

require "dependabot/dependency"

module Dependabot
  # Builds the `error-context` hash sent alongside unknown errors so
  # they can be debugged from Sentry without reproducing the job.
  #
  # The context is diagnostic only and must never affect error grouping. Values
  # are normalised and size-limited; never attach credentials, full URLs,
  # commands or helper output.
  module ErrorReportContext
    extend T::Sig

    Value = T.type_alias { T.any(String, Integer, Float, T::Boolean, T::Array[String]) }
    Context = T.type_alias { T::Hash[String, Value] }

    MAX_STRING_LENGTH = 500
    MAX_ARRAY_LENGTH = 50
    MAX_CAUSE_DEPTH = 5
    REDACTED = "<redacted>"

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

      error_chain(error).reverse_each { |err| context.merge!(attached_context(err)) }

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
