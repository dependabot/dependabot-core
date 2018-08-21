# frozen_string_literal: true

module Dependabot
  class DependabotError < StandardError; end

  #####################
  # Repo leval errors #
  #####################

  class BranchNotFound < DependabotError
    attr_reader :branch_name

    def initialize(branch_name, msg = nil)
      @branch_name = branch_name
      super(msg)
    end

    def file_name
      branch_name.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      branch_name.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  #####################
  # File level errors #
  #####################

  class DependencyFileNotFound < DependabotError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotParseable < DependabotError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotEvaluatable < DependabotError; end
  class DependencyFileNotResolvable < DependabotError; end

  #######################
  # Source level errors #
  #######################

  class PrivateSourceAuthenticationFailure < DependabotError
    attr_reader :source

    def initialize(source)
      @source = source
      msg = "The following source could not be reached as it requires "\
            "authentication (and any provided details were invalid): #{source}"
      super(msg)
    end
  end

  class PrivateSourceTimedOut < DependabotError
    attr_reader :source

    def initialize(source)
      @source = source
      super("The following source timed out: #{source}")
    end
  end

  class PrivateSourceCertificateFailure < DependabotError
    attr_reader :source

    def initialize(source)
      @source = source
      super("Could not verify the SSL certificate for #{source}")
    end
  end

  class MissingEnvironmentVariable < DependabotError
    attr_reader :environment_variable

    def initialize(environment_variable)
      @environment_variable = environment_variable
      super("Missing environment variable #{environment_variable}")
    end
  end

  # Useful for JS file updaters, where the registry API sometimes returns
  # different results to the actual update process
  class InconsistentRegistryResponse < DependabotError; end

  ###########################
  # Dependency level errors #
  ###########################

  class GitDependenciesNotReachable < DependabotError
    attr_reader :dependency_urls

    def initialize(*dependency_urls)
      @dependency_urls =
        dependency_urls.flatten.map { |uri| uri.gsub(/x-access-token.*?@/, "") }

      msg = "The following git URLs could not be retrieved: "\
            "#{dependency_urls.join(', ')}"
      super(msg)
    end
  end

  class GitDependencyReferenceNotFound < DependabotError
    attr_reader :dependency

    def initialize(dependency)
      @dependency = dependency

      msg = "The branch or reference specified for #{dependency} could not "\
            "be retrieved"
      super(msg)
    end
  end

  class PathDependenciesNotReachable < DependabotError
    attr_reader :dependencies

    def initialize(*dependencies)
      @dependencies = dependencies.flatten
      msg = "The following path based dependencies could not be retrieved: "\
            "#{dependencies.join(', ')}"
      super(msg)
    end
  end
end
