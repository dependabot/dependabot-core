Responses from the pub.dev website.

These can be regenerated with:
```bash
for package in cli_util protobuf fixnum path retry; do
  curl --compressed https://pub.dev/api/packages/$package > pub/spec/fixtures/pub_dev_responses/simple/$package.json
done 
```
