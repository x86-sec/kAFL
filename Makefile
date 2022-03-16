# Common helers for kAFL-Fuzzer Python project
# Check install.sh for general kAFL/Nyx install

all: env update install
.PHONY: clean tags

env: .env .west
ifeq ($(PIPENV_ACTIVE), 1)
	@echo "Already inside pipenv. Skipping."
else
	pipenv shell
endif

.env: .west .pipenv manifest/create_env.sh
	pipenv run bash ./manifest/create_env.sh > .env

.west: | .pipenv
	pipenv run west init -l manifest
	pipenv run west update kafl # minimum install for manifest import!

.pipenv:
	sudo apt install python3-pip
	pip install -U pipenv
	pipenv install west
	@touch .pipenv

install:
ifneq ($(PIPENV_ACTIVE), 1)
	@echo "Error: Need to run inside pipenv. Abort."
else
	./kafl/install.sh all
	pip install -e kafl
endif

update:
	west update -k
