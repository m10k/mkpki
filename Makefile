PHONY = install uninstall

ifeq ($(PREFIX), )
	PREFIX = /usr
endif

all:

install:
	mkdir -p           $(DESTDIR)/$(PREFIX)/share/mkpki
	mkdir -p           $(DESTDIR)/$(PREFIX)/bin
	cp mkca.sh         $(DESTDIR)/$(PREFIX)/share/mkpki/.
	cp mkcert.sh       $(DESTDIR)/$(PREFIX)/share/mkpki/.
	cp exportcert.sh   $(DESTDIR)/$(PREFIX)/share/mkpki/.
	chown -R root.root $(DESTDIR)/$(PREFIX)/share/mkpki
	chmod -R 755       $(DESTDIR)/$(PREFIX)/share/mkpki
	ln -sf $(PREFIX)/share/mkpki/mkca.sh       $(DESTDIR)/$(PREFIX)/bin/mkca
	ln -sf $(PREFIX)/share/mkpki/mkcert.sh     $(DESTDIR)/$(PREFIX)/bin/mkcert
	ln -sf $(PREFIX)/share/mkpki/exportcert.sh $(DESTDIR)/$(PREFIX)/bin/exportcert

uninstall:
	rm -f $(DESTDIR)/$(PREFIX)/bin/mkca
	rm -f $(DESTDIR)/$(PREFIX)/bin/mkcert
	rm -f $(DESTDIR)/$(PREFIX)/bin/exportcert
	rm -rf $(DESTDIR)/$(PREFIX)/share/mkpki

.PHONY: $(PHONY)
