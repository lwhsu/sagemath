SAGE_SPKG_CONFIGURE([mpc], [
    AC_CHECK_HEADER(mpc.h, [], [sage_spkg_install_mpc=yes])
dnl mpc_cmp_abs appeared in MPC 1.1.0
    AC_SEARCH_LIBS([mpc_cmp_abs], [mpc], [break], [sage_spkg_install_mpc=yes])
])
