#!/usr/bin/env node

const {argv} = require("node:process")
const fs = require('fs/promises')
const path = require("node:path")

const ECOSYSTEMS = ["Maven"]

async function main(sourceDir, targetDir) {
    console.log(`evaluating ${sourceDir}`)
    const promises = []
    for await (const filename of fs.glob(`${sourceDir}/**/*.json`)) {
        promises.push(new Promise((resolve, reject) => {
            fs.readFile(filename)
              .then(JSON.parse)
              .then(advisoryJSON => {
                if (advisoryJSON.affected.some(affected => ECOSYSTEMS.includes(affected.package.ecosystem)))  {
                    return fs.cp(filename, path.join(targetDir, path.basename(filename)))
                }
                return Promise.resolve()
              })
              .then(resolve)
              .catch(reject)
        }))
    }

    await Promise.all(promises)

    console.log(`finished evaluating ${sourceDir}`)
}

const targetDir = argv.pop()
const sourceDir = argv.pop()

main(sourceDir, targetDir)