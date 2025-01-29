.PHONY = all

all: darwin linux

darwin:
	GOOS=darwin GOARCH=amd64 go build -o go-helpers.darwin64 .

linux:
	GOOS=linux GOARCH=amd64  go build -o go-helpers.linux64 .
