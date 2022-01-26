require 'dependabot/dependency_updaters'

# Creating and registering a dependency updater

module NPM
  class DependencyUpdater < Dependabot::DependencyUpdaters::Base
    class Error < StandardError; end

    def update(dependency:, requirements:)
      system "npm audit fix --package #{dependency.name}"
    rescue => e
      raise Error.new(e.message)
    end
  end
end

Dependabot::DependencyUpdaters.register("npm", NPM::DependencyUpdater)

# Updating a dependency

dependency = Dependency.new(package_url: "pkg://npm/%40react-three/fiber")
requirements = VersionRange.parse(">=7.0.20")

dependency_updater = Dependabot::DependencyUpdaters.for(dependency.package_manager)
dependency_updater.update(dependency: dependency, requirements: requirements)
