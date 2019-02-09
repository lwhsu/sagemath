SAGE_SPKG_CONFIGURE([ncurses], [
    dnl First try checking for ncurses with pkg-config
    PKG_CHECK_MODULES([NCURSES], [ncurses], [sage_spkg_install_ncurses=no], [sage_spkg_install_ncurses=yes])
    ])
