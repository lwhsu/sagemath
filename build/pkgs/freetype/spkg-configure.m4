SAGE_SPKG_CONFIGURE([freetype], [
    dnl First try checking for ncurses with pkg-config
    PKG_CHECK_MODULES([FREETYPE], [freetype2], [sage_spkg_install_freetype=no], [sage_spkg_install_freetype=yes])
    ])
