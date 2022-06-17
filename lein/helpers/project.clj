(defproject helpers "0.1.0"
  :description "dependabot-lein native helper"
  :dependencies [[org.clojure/clojure "1.10.0"]
                 [org.clojure/data.json "1.0.0"]
                 [rewrite-clj "0.6.1"]
                 [leiningen "2.9.4"]]
  :main ^:skip-aot helpers.core
  :target-path "target/%s"
  :profiles {:uberjar {:aot :all}})
