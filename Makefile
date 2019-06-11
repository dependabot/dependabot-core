base:
	docker build -t dependabot/core-base -f Dockerfile.base .

run-base:
	docker build -t dependabot/core-run-base -f Dockerfile.run-base .
