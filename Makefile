PREFIX	=/opt
BINDIR	=${PERFIX}/bin

all:	gallery.pl

check:	gallery.pl
	${MAKE} clean
	ln ~/LEXX/Cast/EvaHabermann/*.{gif,jpg} .
	perl ./gallery.pl  *.{gif,jpg}

clean:
	${RM} *.html *.gif *.jpg

distclean clobber: clean

install:gallery.pl
	${INSTALL} -d ${BINDIR}
	${INSTALL} -m 0644 gallery.pl ${BINDIR}/gallery

uninstall:
	${RM} ${BINDIR}/gallery
