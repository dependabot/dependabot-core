.PHONY = all

all: darwin linux

darwin:
	GOOS=darwin GOARCH=amd64 go build -o updater.darwin64 .

linux:
	GOOS=linux GOARCH=amd64 go build -o updater.linux64 .
