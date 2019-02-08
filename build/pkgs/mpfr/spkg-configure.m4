SAGE_SPKG_CONFIGURE([mpfr], [
    AC_CHECK_HEADER(mpfr.h, [], [sage_spkg_install_mpfr=yes])
dnl mpfr_free_pool appeared in r11922 (Dec 2017) on MPFR svn 
    AC_SEARCH_LIBS([mpfr_free_pool], [mpfr], [break], [sage_spkg_install_mpfr=yes])
])
