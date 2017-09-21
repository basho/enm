REBAR := $(shell command -v rebar3 2>/dev/null)
ifndef REBAR
$(error "rebar3 not found, please install it from https://www.rebar3.org")
endif

all: compile

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean
	rm -rf test.*-temp-data

DIALYZER_APPS = kernel stdlib erts compiler crypto

include tools.mk
