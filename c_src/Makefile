NANOMSG := ./nanomsg-1.0.0
NANOMSG_LIB := lib/libnanomsg.a
NANOMSG_TARBALL := $(NANOMSG).tar.gz
CLEAN := rm -rf $(NANOMSG) bin include lib lib64 share

all: $(NANOMSG_LIB)

$(NANOMSG_LIB): $(NANOMSG_TARBALL)
	set -e ; \
	$(CLEAN) ; \
	tar zxf $(NANOMSG_TARBALL) ; \
	cur=`pwd` ; \
	cd $(NANOMSG) ; \
	mkdir build ; \
	cd build ; \
	cmake .. -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_INSTALL_PREFIX=$$cur -DNN_STATIC_LIB=ON ; \
	cmake --build . ; \
	cmake --build . --target install

.PHONY: clean
clean:
	$(CLEAN)
