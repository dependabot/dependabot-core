(ns dependabot.clojure-helper
  "Reads dependency declarations from project.clj and deps.edn files.

  Files are parsed as data with rewrite-clj and never evaluated. For each
  dependency the position of its version string is returned, so the Ruby side
  can rewrite exactly that string and leave the rest of the file untouched."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [rewrite-clj.node :as n]
            [rewrite-clj.parser :as p])
  (:gen-class))

;; -- Node helpers --

(def ^:private ignored-tags #{:whitespace :newline :comma :comment :uneval})

(defn- unwrap
  "Skips metadata such as ^:replace and returns the annotated node."
  [node]
  (if (and node (#{:meta :meta*} (n/tag node)))
    (recur (last (remove #(ignored-tags (n/tag %)) (n/children node))))
    node))

(defn- children [node]
  (let [node (unwrap node)]
    (if (and node (n/inner? node))
      (remove #(ignored-tags (n/tag %)) (n/children node))
      [])))

(defn- tag [node]
  (some-> (unwrap node) n/tag))

(defn- value
  "Returns the literal value of a token (symbol, keyword, string). Anything
  else, such as an unquoted expression, is code and returns nil."
  [node]
  (let [node (unwrap node)]
    (when (#{:token :multi-line} (some-> node n/tag))
      (n/sexpr node))))

(defn- map-entries
  "Returns [key-value value-node] pairs for a map node."
  [node]
  (when (= :map (tag node))
    (map (fn [[k v]] [(value k) v]) (partition 2 (children node)))))

(defn- label [k]
  (if (keyword? k) (subs (str k) 1) (str k)))

(defn- position [node]
  (let [{:keys [row col end-row end-col]} (meta (unwrap node))]
    {:row row :col col :end_row end-row :end_col end-col}))

;; -- Dependencies --

;; Group for top-level dependencies. Profiles, plugins and aliases get their own.
(def ^:private main-group "dependencies")

(defn- maven-name
  "org.clojure/clojure -> org.clojure:clojure, ring -> ring:ring"
  [lib]
  (let [lib (str lib)
        [group artifact] (if (str/includes? lib "/") (str/split lib #"/" 2) [lib lib])]
    (str group ":" artifact)))

;; Leiningen meta-versions that always resolve to the newest release. Pinning
;; them would change what the user asked for, so they are left alone.
(def ^:private meta-versions #{"RELEASE" "LATEST"})

(defn- dependency [lib version-node groups extra]
  (let [version (value version-node)]
    (when (and (or (symbol? lib) (string? lib))
               (string? version)
               (not (meta-versions version))
               (not (str/includes? (str lib) "$")))
      (merge {:name (maven-name lib) :version version :groups groups}
             (position version-node)
             extra))))

(defn- repository-url
  "A repository is either a URL string or a map with a :url key."
  [node]
  (let [url (or (value node)
                (some (fn [[k v]] (when (= :url k) (value v))) (map-entries node)))]
    (when (string? url) url)))

;; -- project.clj (Leiningen) --

(defn- option
  "Reads an option such as :classifier from the key-values after the version."
  [opts k]
  (some (fn [[opt v]] (when (= k (value opt)) (value v))) (partition 2 opts)))

(defn- lein-dependency [groups node]
  (when (= :vector (tag node))
    (let [[lib-node version-node & opts] (children node)
          classifier (option opts :classifier)
          ;; As in Maven, test-scoped dependencies aren't production dependencies.
          groups (if (and (= [main-group] groups) (= "test" (option opts :scope))) ["test"] groups)]
      (when version-node
        (dependency (value lib-node) version-node groups
                    (when (string? classifier) {:classifier classifier}))))))

(defn- lein-dependencies [groups node]
  (when (= :vector (tag node))
    (keep #(lein-dependency groups %) (children node))))

(defn- lein-repositories [node]
  (let [entries (case (tag node)
                  ;; [["name" "url"] ["name" {:url "url"}]]
                  :vector (keep #(when (= :vector (tag %)) (second (children %))) (children node))
                  ;; {"name" "url"}
                  :map (map second (map-entries node))
                  [])]
    (keep repository-url entries)))

(defn- lein-section
  "Reads the dependency keys of the top-level project or of a profile."
  [entries groups]
  {:dependencies (mapcat (fn [[k v]]
                           (case k
                             (:dependencies :managed-dependencies) (lein-dependencies groups v)
                             :plugins (lein-dependencies (if (= [main-group] groups) ["plugins"] groups) v)
                             nil))
                         entries)
   :repositories (mapcat (fn [[k v]]
                           (when (#{:repositories :plugin-repositories} k) (lein-repositories v)))
                         entries)})

(defn- profile-maps
  "A profile is a map, or a composite vector such as [:base {...}]."
  [node]
  (case (tag node)
    :map [node]
    :vector (filter #(= :map (tag %)) (children node))
    []))

(defn- defproject? [node]
  (and (= :list (tag node))
       (= 'defproject (value (first (children node))))))

(defn- parse-project [content]
  (let [project (first (filter defproject? (children (p/parse-string-all content))))
        _ (when-not project
            (throw (ex-info "No defproject form found in project.clj" {})))
        ;; (defproject name "version" & key-values)
        entries (map (fn [[k v]] [(value k) v]) (partition 2 (drop 3 (children project))))
        profiles (for [[k v] entries
                       :when (= :profiles k)
                       [profile-name profile] (map-entries v)
                       profile-map (profile-maps profile)]
                   (lein-section (map-entries profile-map) [(str "profile:" (label profile-name))]))
        sections (cons (lein-section entries [main-group]) profiles)]
    {:dependencies (vec (mapcat :dependencies sections))
     :repositories (vec (distinct (mapcat :repositories sections)))}))

;; -- deps.edn (Clojure CLI) --

(def ^:private alias-dependency-keys #{:deps :extra-deps :override-deps :replace-deps})

(defn- deps-dependencies [groups node]
  (keep (fn [[lib coord]]
          (when-let [version-node (some (fn [[k v]] (when (= :mvn/version k) v)) (map-entries coord))]
            (dependency lib version-node groups nil)))
        (map-entries node)))

(defn- parse-deps-edn [content]
  (let [root (first (children (p/parse-string-all content)))
        _ (when-not (= :map (tag root))
            (throw (ex-info "deps.edn must contain a map" {})))
        entries (map-entries root)
        main (mapcat (fn [[k v]] (when (= :deps k) (deps-dependencies [main-group] v))) entries)
        aliases (for [[k v] entries
                      :when (= :aliases k)
                      [alias-name alias] (map-entries v)
                      [alias-key deps] (map-entries alias)
                      :when (alias-dependency-keys alias-key)
                      dep (deps-dependencies [(str "alias:" (label alias-name))] deps)]
                  dep)
        repositories (for [[k v] entries
                           :when (= :mvn/repos k)
                           [_ repo] (map-entries v)
                           :let [url (repository-url repo)]
                           :when url]
                       url)]
    {:dependencies (vec (concat main aliases))
     :repositories (vec (distinct repositories))}))

;; -- Entry point --

(defn- run [{:strs [function args]}]
  (case function
    "parse" (let [{:strs [file_name content]} args]
              (if (str/ends-with? file_name ".edn")
                (parse-deps-edn content)
                (parse-project content)))
    (throw (IllegalArgumentException. (str "Unknown function: " function)))))

(defn- error-response [^Throwable e error-class]
  {:error (or (ex-message e) (str e))
   :error_class error-class
   :trace (mapv str (.getStackTrace e))})

(defn -main [& _]
  (let [[response status]
        (try
          [{:result (run (json/read-str (slurp *in*)))} 0]
          ;; rewrite-clj reports syntax errors as ExceptionInfo, as do our own checks.
          (catch clojure.lang.ExceptionInfo e [(error-response e "ParseError") 1])
          (catch Exception e [(error-response e (.getName (class e))) 1]))]
    (json/write response *out*)
    (flush)
    (System/exit status)))
