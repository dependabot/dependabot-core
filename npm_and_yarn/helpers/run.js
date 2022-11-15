#!/usr/bin/env node

const process = require('process')

function output(obj) {
  process.stdout.write(JSON.stringify(obj));
}

function printErrorAndExit(error) {
  output({ error: error.message })
  process.exitCode = 1
}

const input = []
process.stdin.on('data', (data) => input.push(data))
process.stdin.on('end', () => {
  const request = JSON.parse(input.join(''))
  const [manager, functionName] = request.function.split(':')
  const helpers = require(`./lib/${manager}`)
  const func = helpers[functionName]
  if (!func) {
    printErrorAndExit(new Error(`Invalid function ${request.function}`))
    return
  }

  func
    .apply(null, request.args)
    .then((result) => output({ result }))
    .catch(printErrorAndExit)
})

process.once('uncaughtException', printErrorAndExit)
