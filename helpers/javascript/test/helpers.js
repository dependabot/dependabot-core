module.exports = {
  loadFixture: (path) => fs.readFileSync(path).toString()
}
