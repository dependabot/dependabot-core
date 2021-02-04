const path = require("path");
// NOTE: This is a hack to get around the fact that we can't require un-exported
// methods from npm
const errorMessage = require(path.join(
  __dirname,
  "../../node_modules/npm7/lib/utils/error-message.js"
));

const flattenMessage = (msg) =>
  msg.map((logline) => logline.slice(1).join(" ")).join("\n");

const formatErrorMessage = (er) => {
  if (typeof er === "string") {
    return er;
  }

  if (!er.code) {
    const matchErrorCode = er.message.match(/^(?:Error: )?(E[A-Z]+)/);
    er.code = matchErrorCode && matchErrorCode[1];
  }

  let errors = [];
  const msg = errorMessage(er);
  errors.push(flattenMessage(msg.summary));
  errors.push(flattenMessage(msg.detail));
  // npm 6 format
  errors.push("exited with error code: " + er.code);

  return errors.join("\n");
};

module.exports = {
  formatErrorMessage,
};
