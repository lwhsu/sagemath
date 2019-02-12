SAGE_SPKG_CONFIGURE([flint], [
    AC_CHECK_HEADER(flint/flint.h, [], [sage_spkg_install_flint=yes])
dnl fmpz_mat_is_hadamard appears in Flint 2.5.0
    AC_SEARCH_LIBS([fmpz_mat_is_hadamard], [flint], [], [sage_spkg_install_flint=yes])
dnl this only comes up if flint is linked with NTL
    AC_SEARCH_LIBS([fmpz_poly_get_ZZX], [flint], [break], [sage_spkg_install_flint=yes])
])
