# typed: strong
# frozen_string_literal: true

module Dependabot
  module Clojure
    ECOSYSTEM = "clojure"

    LEIN_FILE_NAME = "project.clj"
    DEPS_FILE_NAME = "deps.edn"

    # Group of top-level dependencies, as reported by the native helper.
    MAIN_GROUP = "dependencies"

    # Clojure libraries are published to Clojars, and Java libraries to Maven Central.
    CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"
    CLOJARS_REPO_URL = "https://repo.clojars.org"
  end
end
