.PHONY: init build verify check

init:
	./scripts/init-project.sh

build:
	./scripts/build-target.sh

verify:
	./workspace/scripts/verify_target_identity.sh

check:
	./scripts/check-release.sh
