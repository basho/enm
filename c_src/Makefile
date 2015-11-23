NANOMSG := ./nanomsg-0.8-beta
NANOMSG_LIB := lib/libnanomsg.a
NANOMSG_TARBALL := $(NANOMSG).tar.gz
CLEAN := rm -rf $(NANOMSG) bin include lib

all: $(NANOMSG_LIB)

$(NANOMSG_LIB): $(NANOMSG_TARBALL)
	set -e ; \
	$(CLEAN) ; \
	tar zxf $(NANOMSG_TARBALL) ; \
	cur=`pwd` ; \
	cd $(NANOMSG) ; \
	CFLAGS="$$DRV_CFLAGS" ./configure --prefix=$$cur ; \
	make -j4 all && make install

.PHONY: clean
clean:
	$(CLEAN)
