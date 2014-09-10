REBAR = rebar

all: compile

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean
	rm -rf test.*-temp-data

DIALYZER_APPS = kernel stdlib erts compiler crypto

include tools.mk
