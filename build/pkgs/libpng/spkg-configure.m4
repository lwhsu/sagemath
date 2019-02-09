SAGE_SPKG_CONFIGURE([libpng], [
    dnl First try checking for libpng with pkg-config
    PKG_CHECK_MODULES([LIBPNG], [libpng16], [], [
    dnl Fallback to manually grubbing around for headers and libs
                    AC_CHECK_HEADERS([libpng16/png.h], [sage_spkg_install_libpng=no; break], [sage_spkg_install_libpng=yes])
                    AC_SEARCH_LIBS([png_get_io_ptr], [libpng16], [], [sage_spkg_install_libpng=yes])
    ])
    ])
