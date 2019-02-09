SAGE_SPKG_CONFIGURE([ntl], [
    LB_CHECK_NTL(10.3, [sage_spkg_install_ntl=no], [sage_spkg_install_ntl=yes])
    ])
