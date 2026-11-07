/* eslint-disable @typescript-eslint/no-explicit-any */
export function runAsync(
  obj: any,
  method: (...args: any[]) => void,
  args: any[]
): Promise<any[]> {
  return new Promise((resolve, reject) => {
    const cb = (err: Error | null, ...returnValues: any[]) => {
      if (err) {
        reject(err);
      } else {
        resolve(returnValues);
      }
    };
    method.apply(obj, [...args, cb]);
  });
}

export function muteStderr(): () => void {
  const original = process.stderr.write;
  process.stderr.write = (() => {}) as unknown as typeof process.stderr.write;
  return () => {
    process.stderr.write = original;
  };
}
