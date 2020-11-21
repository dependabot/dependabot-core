(defproject clj-http "3.11.1-SNAPSHOT"
  :description "A Clojure HTTP library wrapping the Apache HttpComponents client."
  :url "https://github.com/dakrone/clj-http/"
  :license {:name "The MIT License"
            :url "http://opensource.org/licenses/mit-license.php"
            :distribution :repo}
  :global-vars {*warn-on-reflection* false}
  :min-lein-version "2.0.0"
  :exclusions [org.clojure/clojure]
  :dependencies [[org.apache.httpcomponents/httpcore "4.4.13"]
                 [org.apache.httpcomponents/httpclient "4.5.13"]
                 [org.apache.httpcomponents/httpclient-cache "4.5.13"]
                 [org.apache.httpcomponents/httpasyncclient "4.1.4"]
                 [org.apache.httpcomponents/httpmime "4.5.13"]
                 [commons-codec "1.12"]
                 [commons-io "2.6"]
                 [slingshot "0.12.2"]
                 [potemkin "0.4.5"]]
  :resource-paths ["resources"]
  :profiles {:dev {:dependencies [;; optional deps
                                  [cheshire "5.9.0"]
                                  [crouton "0.1.2" :exclusions [[org.jsoup/jsoup]]]
                                  [org.jsoup/jsoup "1.11.3"]
                                  [org.clojure/tools.reader "1.3.2"]
                                  [com.cognitect/transit-clj "0.8.313"]
                                  [ring/ring-codec "1.1.2"]
                                  ;; other (testing) deps
                                  [org.clojure/clojure "1.10.0"]
                                  [org.clojure/tools.logging "0.4.0"]
                                  [ring/ring-jetty-adapter "1.7.1"]
                                  [ring/ring-devel "1.7.1"]
                                  ;; caching example deps
                                  [org.clojure/core.cache "0.7.2"]
                                  ;; logging
                                  [org.apache.logging.log4j/log4j-api "2.11.2"]
                                  [org.apache.logging.log4j/log4j-core "2.11.2"]
                                  [org.apache.logging.log4j/log4j-1.2-api "2.11.2"]]
                   :plugins [[lein-ancient "0.6.15"]
                             [jonase/eastwood "0.2.5"]
                             [lein-kibit "0.1.5"]
                             [lein-nvd "0.5.2"]]}
             :1.6 {:dependencies [[org.clojure/clojure "1.6.0"]]}
             :1.7 {:dependencies [[org.clojure/clojure "1.7.0"]]}
             :1.8 {:dependencies [[org.clojure/clojure "1.8.0"]]}
             :1.9 {:dependencies [[org.clojure/clojure "1.9.0"]]}
             :1.10 {:dependencies [[org.clojure/clojure "1.10.1"]]}}
  :aliases {"all" ["with-profile" "dev,1.6:dev,1.7:dev,1.8:dev,1.9:dev,1.10:dev"]}
  :plugins [[codox "0.6.4"]]
  :test-selectors {:default  #(not (:integration %))
                   :integration :integration
                   :all (constantly true)})
