/**
 * Writes data to stream, respecting backpressure. Callback will be called when it's ok to resume writing.
 */
const writeRespectingBackpressure = (stream, data, callback) => {
  if (!stream.write(data)) {
    stream.once('drain', callback)
  } else {
    process.nextTick(callback)
  }
}

/**
 * Writes data to stream, respecting backpressure but flushing as soon as possible.
 */
const writeASAP = (stream, data) => {
  stream.cork()
  writeRespectingBackpressure(stream, data, stream.uncork.bind(stream))
}

module.exports = {
    writeRespectingBackpressure,
    writeASAP,
}
