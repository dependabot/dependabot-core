# typed: strong
# frozen_string_literal: true

# These all need to be required so the various classes can be registered in a
# lookup table of package manager names to concrete classes.
require "dependabot/clojure/package_manager"
require "dependabot/clojure/file_fetcher"

require "dependabot/dependency"
Dependabot::Dependency
  .register_production_check(Dependabot::Clojure::ECOSYSTEM, ->(_) { true })
