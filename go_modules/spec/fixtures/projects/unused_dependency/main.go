package main

import (
  log "github.com/sirupsen/logrus"
  "github.com/pterodactyl/wings/parser" // not used
)

func main() {
  log.WithFields(log.Fields{
    "animal": "walrus",
  }).Info("A walrus appears")
}
