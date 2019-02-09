SAGE_SPKG_CONFIGURE([readline], [
    dnl First try checking for readline with pkg-config
    PKG_CHECK_MODULES([READLINE], [readline], [sage_spkg_install_readline=no], [sage_spkg_install_readline=yes])
    ])
