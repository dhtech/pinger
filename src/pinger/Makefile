clean:
	rm -fr build/

all:
	true

test:
	true

install:
	python3 setup.py install --root $(DESTDIR) $(COMPILE)
	mkdir -p $(DESTDIR)/opt/pinger/src/
	cp pingerd $(DESTDIR)/opt/pinger/
	chmod +x $(DESTDIR)/opt/pinger/pingerd
