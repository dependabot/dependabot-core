(ns helpers.core
  (:require [leiningen.pom :as pom]
            [clojure.java.io :as io]
            [rewrite-clj.zip :as zip]
            [clojure.data.json :as json]
            [leiningen.core.project :as project])
  (:gen-class))

(defn- match? [dep-name dep-version {:keys [dependency previous]}]
  (and (= previous dep-version)
       (or (= dependency dep-name)
           (= dependency (str dep-name "/" dep-name)))))

(defn- update-dependency [dependencies dep]
  (let [dep-name (-> dep (zip/get 0) zip/sexpr str)
        dep-version (-> dep (zip/get 1) zip/sexpr str)]
    (if-let [updated (->> dependencies
                          (filter (partial match? dep-name dep-version))
                          (first))]
      (zip/assoc dep 1 (:version updated))
      dep)))

(defn update-dependencies [{:keys [file dependencies]}]
  (-> file
      (zip/of-string)
      (zip/find-value zip/next 'defproject)
      (zip/find-value :dependencies)
      (zip/right)
      (#(zip/map (partial update-dependency dependencies) %))
      (zip/root-string)))

(defn generate-pom [{:keys [file]}]
  (let [proj (project/read-raw (io/reader (char-array file)))]
    ;; TODO: Merge all profiles dependencies into main dependencies
    (pom/make-pom (select-keys proj [:repositories :dependencies :profiles :version]))))

(defn -main
  [& args]
  (let [{:keys [function args]} (json/read *in* :key-fn keyword)
        fun (case function
              "generate_pom" generate-pom
              "update_dependencies" update-dependencies)]
  (json/write {:result (fun args)} *out*))
  (flush))
