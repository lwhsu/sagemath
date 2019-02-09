SAGE_SPKG_CONFIGURE([arb], [
    AC_CHECK_HEADER(arb.h, [], [sage_spkg_install_arb=yes])
dnl have to ask for a good test function 
    AC_SEARCH_LIBS([acb_dirichlet_powsum_term], [arb], [break], [sage_spkg_install_arb=yes])
])
