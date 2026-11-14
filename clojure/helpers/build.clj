(ns build
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/clojure-helper.jar")
(def basis (delay (b/create-basis {:project "deps.edn"})))

(defn uber [_]
  (b/delete {:path "target"})
  (b/compile-clj {:basis @basis
                  :src-dirs ["src"]
                  :class-dir class-dir
                  :ns-compile '[dependabot.clojure-helper]})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :basis @basis
           :main 'dependabot.clojure-helper}))
