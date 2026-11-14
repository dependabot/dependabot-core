(def version "1.0")

;; Example Leiningen project
(defproject example/app "0.1.0-SNAPSHOT"
  :description "Example app"
  :min-lein-version "2.9.0"
  :repositories [["private" {:url "https://repo.example.com/maven/" :creds :gpg}]]
  :plugin-repositories [["plugins" "https://plugins.example.com/repo"]]
  :dependencies [[org.clojure/clojure "1.11.1"]
                 [ring/ring-core "1.9.6" :exclusions [commons-io]]
                 #_[ignored/dependency "0.0.1"]
                 ^:inline-dep [cheshire "5.11.0"]
                 [org.lwjgl/lwjgl "3.3.1" :classifier "natives-linux"]
                 [unquoted/version ~version]
                 [meta/version "RELEASE"]]
  :plugins [[lein-ancient "1.0.0-RC3"]]
  :profiles {:dev {:dependencies [[ring/ring-mock "0.4.0"]
                                  [ring/ring-core "1.9.6"]]}
             :test [:base {:dependencies [[org.clojure/test.check "1.1.1"]]}]})
