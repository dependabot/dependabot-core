import NoopReporter = from("@dependabot/yarn-lib/lib/reporters.js");
import LanguageKeys = from("@dependabot/yarn-lib/lib/lan/en.js");

export default class DependabotReporter extends NoopReporter {
  lang(key: LanguageKeys, ...args: Array<mixed>): string {
    const msg = languages[this.language][key] || languages.en[key];
    if (!msg) {
      throw new ReferenceError(`Unknown language key ${key}`);
    }

    // stringify args
    const stringifiedArgs = stringifyLangArgs(args);

    // replace $0 placeholders with args
    return msg.replace(/\$(\d+)/g, (str, i: number) => {
      return stringifiedArgs[i];
    });
  }
}
