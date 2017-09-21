REBAR_URL=https://s3.amazonaws.com/rebar3/rebar3
REBAR = $(shell pwd)/rebar3

all: $(REBAR) compile

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean
	rm -rf test.*-temp-data

DIALYZER_APPS = kernel stdlib erts compiler crypto

$(REBAR):
	curl -Lo rebar3 $(REBAR_URL) || wget $(REBAR_URL)
	chmod a+x rebar3

upgrade_rebar:
	$(REBAR) local upgrade


include tools.mk
