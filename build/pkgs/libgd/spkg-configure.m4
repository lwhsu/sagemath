SAGE_SPKG_CONFIGURE([libgd], [
    dnl First try checking for libpng with pkg-config
    PKG_CHECK_MODULES([LIBGD], [libgd], [sage_spkg_install_libgd=no], [sage_spkg_install_libgd=yes])
])
