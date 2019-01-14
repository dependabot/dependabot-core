/*
  Copyright (C) 2017 Jorge Martinez Hernandez

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU Affero General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

package main

import (
  "os"
  "os/signal"

  "github.com/varddum/syndication/admin"
  "github.com/varddum/syndication/cmd"
  "github.com/varddum/syndication/database"
  "github.com/varddum/syndication/server"
  "github.com/varddum/syndication/sync"

  log "github.com/sirupsen/logrus"
)

var intSignal chan os.Signal

func main() {
  if err := cmd.Execute(); err != nil {
    log.Error(err)
    os.Exit(1)
  }

  config := cmd.EffectiveConfig

  if err := database.Init(config.Database.Type, config.Database.Connection); err != nil {
    log.Error(err)
    os.Exit(1)
  }

  sync := sync.NewService(config.Sync.Interval)

  if config.Admin.Enable {
    adminServ, err := admin.NewService(config.Admin.SocketPath)
    if err != nil {
      log.Error(err)
      os.Exit(1)
    }
    adminServ.Start()

    defer adminServ.Stop()
  }

  sync.Start()

  listenForInterrupt()

  server := server.NewServer(config.AuthSecret)
  go func() {
    for sig := range intSignal {
      if sig == os.Interrupt || sig == os.Kill {
        err := server.Stop()
        if err != nil {
          log.Error(err)
          os.Exit(1)
        }
      }
    }
  }()

  log.Info("Starting server on ", config.Host.Address, ":", config.Host.Port)

  err := server.Start(
    config.Host.Address,
    config.Host.Port)

  if err != nil {
    log.Error(err)
    os.Exit(1)
  }
}

func listenForInterrupt() {
  intSignal = make(chan os.Signal, 1)
  signal.Notify(intSignal, os.Interrupt)
}
