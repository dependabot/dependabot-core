export function runAsync(obj, method, args) {
  return new Promise((resolve, reject) => {
    const cb = (err, ...returnValues) => {
      if (err) {
        reject(err);
      } else {
        resolve(returnValues);
      }
    };
    method.apply(obj, [...args, cb]);
  });
}

export function muteStderr() {
  const original = process.stderr.write;
  process.stderr.write = () => {};
  return () => {
    process.stderr.write = original;
  };
}
