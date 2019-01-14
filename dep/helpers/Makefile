.PHONY = all

all: darwin linux

darwin:
	GO111MODULE=on GOOS=darwin GOARCH=amd64 go build -o go-helpers.darwin64 .

linux:
	GO111MODULE=on GOOS=linux GOARCH=amd64  go build -o go-helpers.linux64 .
