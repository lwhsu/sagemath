# -*- coding: utf-8 -*-
r"""
Database of strongly regular graphs

This module manages a database associating to a set of four integers
`(v,k,\lambda,\mu)` a strongly regular graphs with these parameters, when one
exists.

Using Andries Brouwer's `database of strongly regular graphs
<http://www.win.tue.nl/~aeb/graphs/srg/srgtab.html>`__, it can also return
non-existence results. Note that some constructions are missing, and that some
strongly regular graphs that exist in the database cannot be automatically built
by Sage. Help us if you know any.

.. NOTE::

    Any missing/incorrect information in the database must be reported to
    `Andries E. Brouwer <http://www.win.tue.nl/~aeb/>`__ directly, in order to
    have a unique and updated source of information.

REFERENCES:

.. [BvL84] A. Brouwer, J van Lint,
   Strongly regular graphs and partial geometries,
   Enumeration and design,
   (Waterloo, Ont., 1982) (1984): 85-122.
   http://oai.cwi.nl/oai/asset/1817/1817A.pdf

Functions
---------
"""
from sage.categories.sets_cat import EmptySetError
from sage.misc.unknown import Unknown
from sage.rings.arith import is_square
from sage.rings.arith import is_prime_power
from sage.misc.cachefunc import cached_function
from sage.combinat.designs.orthogonal_arrays import orthogonal_array
from sage.combinat.designs.bibd import balanced_incomplete_block_design
from sage.graphs.generators.smallgraphs import McLaughlinGraph
from sage.graphs.generators.smallgraphs import CameronGraph
from sage.graphs.generators.smallgraphs import M22Graph
from sage.graphs.generators.smallgraphs import SimsGewirtzGraph
from sage.graphs.generators.smallgraphs import HoffmanSingletonGraph
from sage.graphs.generators.smallgraphs import HigmanSimsGraph
from sage.graphs.generators.smallgraphs import LocalMcLaughlinGraph
from sage.graphs.generators.smallgraphs import MathonStronglyRegularGraph
from sage.graphs.generators.smallgraphs import SuzukiGraph
from sage.graphs.graph import Graph
from libc.math cimport sqrt, floor
from sage.matrix.constructor import Matrix
from sage.rings.finite_rings.constructor import FiniteField as GF
from sage.coding.linear_code import LinearCode
from sage.rings.sum_of_squares cimport two_squares_c
from libc.stdint cimport uint_fast32_t

cdef dict _brouwer_database = None

@cached_function
def is_paley(int v,int k,int l,int mu):
    r"""
    Test whether some Paley graph is `(v,k,\lambda,\mu)`-strongly regular.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_paley
        sage: t = is_paley(13,6,2,3); t
        (..., 13)
        sage: g = t[0](*t[1:]); g
        Paley graph with parameter 13: Graph on 13 vertices
        sage: g.is_strongly_regular(parameters=True)
        (13, 6, 2, 3)
        sage: t = is_paley(5,5,5,5); t
    """
    if (v%4 == 1 and is_prime_power(v) and
        k   == (v-1)/2 and
        l   == (v-5)/4 and
        mu  == (v-1)/4):
        from sage.graphs.generators.families import PaleyGraph
        return (lambda q : PaleyGraph(q),v)

@cached_function
def is_mathon_PC_srg(int v,int k,int l,int mu):
    r"""
    Test whether some Mathon's Pseudocyclic s.r.g. is `(v,k,\lambda,\mu)`-strongly regular.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    .. TODO::

        The current implementation only gives a subset of all possible graphs that can be
        obtained using this construction. A  full implementation should rely on a database
        of conference matrices (or, equivalently, on a database of s.r.g.'s with parameters
        `(4t+1,2t,t-1,t)`. Currently we make an extra assumtion that `4t+1` is a prime power.
        The first case where we miss a construction is `t=11`, where we could (recursively)
        use the graph for `t=1` to construct a graph on 83205 vertices.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_mathon_PC_srg
        sage: t = is_mathon_PC_srg(45,22,10,11); t
        (..., 1)
        sage: g = t[0](*t[1:]); g
        Mathon's PC SRG on 45 vertices: Graph on 45 vertices
        sage: g.is_strongly_regular(parameters=True)
        (45, 22, 10, 11)

    TESTS::

        sage: t = is_mathon_PC_srg(5,5,5,5); t
        sage: mu = 1895  # t=5 case -- the construction cannot work
        sage: t = is_mathon_PC_srg(4*mu+1,2*mu,mu-1,mu); t
    """
    cdef int t
    if (v%4 == 1 and
        k   == (v-1)/2 and
        l   == (v-5)/4 and
        mu  == (v-1)/4):
        from sage.rings.integer_ring import ZZ
        K = ZZ['x']
        x = K.gen()
        rpoly = filter(lambda w: w[0]>0, (x*(4*x*(4*x-1)-1)-mu).roots())
        if rpoly != []:
            t = rpoly[0][0]
            if (is_prime_power(4*t-1) and
                is_prime_power(4*t+1)): # extra assumption in TODO!
                from sage.graphs.generators.families import \
                                    MathonPseudocyclicStronglyRegularGraph
                return (lambda q : MathonPseudocyclicStronglyRegularGraph(q),t)

@cached_function
def is_orthogonal_array_block_graph(int v,int k,int l,int mu):
    r"""
    Test whether some (pseudo)Orthogonal Array graph is `(v,k,\lambda,\mu)`-strongly regular.

    We know how to construct graphs with parameters of an Orthogonal Array (`OA(m,n)`),
    also known as Latin squares graphs `L_m(n)`, in several cases where no orthogonal
    array is known, or even in some cases for which they are known not to exist.

    Such graphs are usually called pseudo-Latin squares graphs. Namely, Sage
    can construct a graph with parameters of an `OA(m,n)`-graph whenever there
    exists a skew-Hadamard matrix of order `n+1`, and `m=(n+1)/2` or `m=(n-1)/2`.
    The construction in the former case is due to Goethals-Seidel [BvL84]_, and in the
    latter case due to Pasechnik [Pa92]_.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_orthogonal_array_block_graph
        sage: t = is_orthogonal_array_block_graph(64, 35, 18, 20); t
        (..., 5, 8)
        sage: g = t[0](*t[1:]); g
        OA(5,8): Graph on 64 vertices
        sage: g.is_strongly_regular(parameters=True)
        (64, 35, 18, 20)
        sage: t=is_orthogonal_array_block_graph(225,98,43,42); t
        (..., 4)
        sage: g = t[0](*t[1:]); g
        Pasechnik Graph_4: Graph on 225 vertices
        sage: g.is_strongly_regular(parameters=True)
        (225, 98, 43, 42)
        sage: t=is_orthogonal_array_block_graph(225,112,55,56); t
        (..., 4)
        sage: g = t[0](*t[1:]); g
        skewhad^2_4: Graph on 225 vertices
        sage: g.is_strongly_regular(parameters=True)
        (225, 112, 55, 56)

        sage: t = is_orthogonal_array_block_graph(5,5,5,5); t

    REFERENCE:

    .. [Pa92] D. V. Pasechnik,
      Skew-symmetric association schemes with two classes and strongly
      regular graphs of type `L_{2n-1}(4n- 1)`,
      Acta Applicandaie Math. 29(1992), 129-138
    """
    # notations from
    # http://www.win.tue.nl/~aeb/graphs/OA.html
    from sage.combinat.matrices.hadamard_matrix import skew_hadamard_matrix
    try:
        m, n = latin_squares_graph_parameters(v,k,l,mu)
    except:
        return
    if orthogonal_array(m,n,existence=True):
        from sage.graphs.generators.intersection import OrthogonalArrayBlockGraph
        return (lambda m,n : OrthogonalArrayBlockGraph(m, n), m,n)

    elif n>2 and skew_hadamard_matrix(n+1, existence=True):
        if m==(n+1)/2:
            from sage.graphs.generators.families import SquaredSkewHadamardMatrixGraph as G
        elif m==(n-1)/2:
            from sage.graphs.generators.families import PasechnikGraph as G
        else:
            return
        return (G, (n+1)/4)

@cached_function
def is_johnson(int v,int k,int l,int mu):
    r"""
    Test whether some Johnson graph is `(v,k,\lambda,\mu)`-strongly regular.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_johnson
        sage: t = is_johnson(10,6,3,4); t
        (..., 5)
        sage: g = t[0](*t[1:]); g
        Johnson graph with parameters 5,2: Graph on 10 vertices
        sage: g.is_strongly_regular(parameters=True)
        (10, 6, 3, 4)

        sage: t = is_johnson(5,5,5,5); t
    """
    # Using notations of http://www.win.tue.nl/~aeb/graphs/Johnson.html
    #
    # J(n,m) has parameters v = m(m – 1)/2, k = 2(m – 2), λ = m – 2, μ = 4.
    m = l + 2
    if (mu == 4 and
        k  == 2*(m-2) and
        v  == m*(m-1)/2):
        from sage.graphs.generators.families import JohnsonGraph
        return (lambda m: JohnsonGraph(m,2), m)

@cached_function
def is_steiner(int v,int k,int l,int mu):
    r"""
    Test whether some Steiner graph is `(v,k,\lambda,\mu)`-strongly regular.

    A Steiner graph is the intersection graph of a Steiner set system. For more
    information, see http://www.win.tue.nl/~aeb/graphs/S.html.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_steiner
        sage: t = is_steiner(26,15,8,9); t
        (..., 13, 3)
        sage: g = t[0](*t[1:]); g
        Intersection Graph: Graph on 26 vertices
        sage: g.is_strongly_regular(parameters=True)
        (26, 15, 8, 9)

        sage: t = is_steiner(5,5,5,5); t
    """
    # Using notations from http://www.win.tue.nl/~aeb/graphs/S.html
    #
    # The block graph of a Steiner 2-design S(2,m,n) has parameters:
    # v = n(n-1)/m(m-1), k = m(n-m)/(m-1), λ = (m-1)^2 + (n-1)/(m–1)–2, μ = m^2.
    if mu <= 1 or not is_square(mu):
        return
    m = int(sqrt(mu))
    n = (k*(m-1))//m+m
    if (v == (n*(n-1))/(m*(m-1)) and
        k == m*(n-m)/(m-1) and
        l == (m-1)**2 + (n-1)/(m-1)-2 and
        balanced_incomplete_block_design(n,m,existence=True)):
        from sage.graphs.generators.intersection import IntersectionGraph
        return (lambda n,m: IntersectionGraph(map(frozenset,balanced_incomplete_block_design(n,m))),n,m)

@cached_function
def is_affine_polar(int v,int k,int l,int mu):
    r"""
    Test whether some Affine Polar graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see http://www.win.tue.nl/~aeb/graphs/VO.html.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_affine_polar
        sage: t = is_affine_polar(81,32,13,12); t
        (..., 4, 3)
        sage: g = t[0](*t[1:]); g
        Affine Polar Graph VO^+(4,3): Graph on 81 vertices
        sage: g.is_strongly_regular(parameters=True)
        (81, 32, 13, 12)

        sage: t = is_affine_polar(5,5,5,5); t
    """
    from sage.rings.arith import divisors
    # Using notations from http://www.win.tue.nl/~aeb/graphs/VO.html
    #
    # VO+(2e,q) has parameters: v = q^(2e), k = (q^(e−1) + 1)(q^e − 1), λ =
    # q(q^(e−2) + 1)(q^(e−1) − 1) + q − 2, μ = q^(e−1)(q^(e−1) + 1)
    #
    # VO−(2e,q) has parameters v = q^(2e), k = (q^(e−1) - 1)(q^e + 1), λ =
    # q(q^(e−2) - 1)(q^(e−1) + 1) + q − 2, μ = q^(e−1)(q^(e−1) - 1)
    if (not is_square(v) or
        not is_prime_power(v)):
        return
    prime,power = is_prime_power(v,get_data=True)
    if power%2:
        return
    for e in divisors(power/2):
        q = prime**(power//(2*e))
        assert v == q**(2*e)
        if (k == (q**(e-1) + 1)*(q**e-1) and
            l == q*(q**(e-2) + 1)*(q**(e-1)-1)+q-2 and
            mu== q**(e-1)*(q**(e-1) + 1)):
            from sage.graphs.generators.classical_geometries import AffineOrthogonalPolarGraph
            return (lambda d,q : AffineOrthogonalPolarGraph(d,q,sign='+'),2*e,q)
        if (k == (q**(e-1) - 1)*(q**e+1) and
            l == q*(q**(e-2)- 1)*(q**(e-1)+1)+q-2 and
            mu== q**(e-1)*(q**(e-1) - 1)):
            from sage.graphs.generators.classical_geometries import AffineOrthogonalPolarGraph
            return (lambda d,q : AffineOrthogonalPolarGraph(d,q,sign='-'),2*e,q)

@cached_function
def is_orthogonal_polar(int v,int k,int l,int mu):
    r"""
    Test whether some Orthogonal Polar graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see http://www.win.tue.nl/~aeb/graphs/srghub.html.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_orthogonal_polar
        sage: t = is_orthogonal_polar(85, 20, 3, 5); t
        (<function OrthogonalPolarGraph at ...>, 5, 4, '')
        sage: g = t[0](*t[1:]); g
        Orthogonal Polar Graph O(5, 4): Graph on 85 vertices
        sage: g.is_strongly_regular(parameters=True)
        (85, 20, 3, 5)

        sage: t = is_orthogonal_polar(5,5,5,5); t

    TESTS:

    All of ``O(2m+1,q)``, ``O^+(2m,q)`` and ``O^-(2m,q)`` appear::

        sage: is_orthogonal_polar(85, 20, 3, 5)
        (<function OrthogonalPolarGraph at ...>, 5, 4, '')
        sage: is_orthogonal_polar(119,54,21,27)
        (<function OrthogonalPolarGraph at ...>, 8, 2, '-')
        sage: is_orthogonal_polar(130,48,20,16)
        (<function OrthogonalPolarGraph at ...>, 6, 3, '+')

    """
    from sage.rings.arith import divisors
    r,s = eigenvalues(v,k,l,mu)
    if r is None:
        return
    q_pow_m_minus_one = -s-1 if abs(s) > r else r+1

    if is_prime_power(q_pow_m_minus_one):
        prime,power = is_prime_power(q_pow_m_minus_one,get_data=True)
        for d in divisors(power):
            q = prime**d
            m = (power//d)+1

            # O(2m+1,q)
            if (v == (q**(2*m)-1)/(q-1)              and
                k == q*(q**(2*m-2)-1)/(q-1)          and
                l == q**2*(q**(2*m-4)-1)/(q-1) + q-1 and
                mu== (q**(2*m-2)-1)/(q-1)):
                from sage.graphs.generators.classical_geometries import OrthogonalPolarGraph
                return (OrthogonalPolarGraph, 2*m+1, q, "")

            # O^+(2m,q)
            if (v ==   (q**(2*m-1)-1)/(q-1) + q**(m-1)   and
                k == q*(q**(2*m-3)-1)/(q-1) + q**(m-1) and
                k == q**(2*m-3) + l + 1                  and
                mu== k/q):
                from sage.graphs.generators.classical_geometries import OrthogonalPolarGraph
                return (OrthogonalPolarGraph, 2*m, q, "+")

            # O^+(2m+1,q)
            if (v ==   (q**(2*m-1)-1)/(q-1) - q**(m-1)   and
                k == q*(q**(2*m-3)-1)/(q-1) - q**(m-1) and
                k == q**(2*m-3) + l + 1                  and
                mu== k/q):
                from sage.graphs.generators.classical_geometries import OrthogonalPolarGraph
                return (OrthogonalPolarGraph, 2*m, q, "-")

@cached_function
def is_goethals_seidel(int v,int k,int l,int mu):
    r"""
    Test whether some
    :func:`~sage.graphs.graph_generators.GraphGenerators.GoethalsSeidelGraph` graph is
    `(v,k,\lambda,\mu)`-strongly regular.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_goethals_seidel
        sage: t = is_goethals_seidel(28, 15, 6, 10); t
        [<function GoethalsSeidelGraph at ...>, 3, 3]
        sage: g = t[0](*t[1:]); g
        Graph on 28 vertices
        sage: g.is_strongly_regular(parameters=True)
        (28, 15, 6, 10)

        sage: t = is_goethals_seidel(256, 135, 70, 72); t
        [<function GoethalsSeidelGraph at ...>, 2, 15]
        sage: g = t[0](*t[1:]); g
        Graph on 256 vertices
        sage: g.is_strongly_regular(parameters=True)
        (256, 135, 70, 72)

        sage: t = is_goethals_seidel(5,5,5,5); t

    TESTS::

        sage: for p in [(16, 9, 4, 6), (28, 15, 6, 10), (64, 35, 18, 20), (120, 63, 30, 36),
        ....:           (144, 77, 40, 42), (256, 135, 70, 72), (400, 209, 108, 110),
        ....:           (496, 255, 126, 136), (540, 275, 130, 150), (576, 299, 154, 156),
        ....:           (780, 399, 198, 210), (784, 405, 208, 210), (976, 495, 238, 264)]:
        ....:     print is_goethals_seidel(*p)
        [<function GoethalsSeidelGraph at ...>, 2, 3]
        [<function GoethalsSeidelGraph at ...>, 3, 3]
        [<function GoethalsSeidelGraph at ...>, 2, 7]
        [<function GoethalsSeidelGraph at ...>, 3, 7]
        [<function GoethalsSeidelGraph at ...>, 2, 11]
        [<function GoethalsSeidelGraph at ...>, 2, 15]
        [<function GoethalsSeidelGraph at ...>, 2, 19]
        [<function GoethalsSeidelGraph at ...>, 3, 15]
        [<function GoethalsSeidelGraph at ...>, 5, 11]
        [<function GoethalsSeidelGraph at ...>, 2, 23]
        [<function GoethalsSeidelGraph at ...>, 3, 19]
        [<function GoethalsSeidelGraph at ...>, 2, 27]
        [<function GoethalsSeidelGraph at ...>, 5, 15]
    """
    from sage.combinat.designs.bibd import balanced_incomplete_block_design
    from sage.combinat.matrices.hadamard_matrix import hadamard_matrix

    # here we guess the parameters v_bibd,k_bibd and r_bibd of the block design
    #
    # - the number of vertices v is equal to v_bibd*(r_bibd+1)
    # - the degree k of the graph is equal to k=(v+r_bibd-1)/2

    r_bibd = k - (v-1-k)
    v_bibd = v//(r_bibd+1)
    k_bibd = (v_bibd-1)/r_bibd + 1 if r_bibd>0 else -1

    if (v   == v_bibd*(r_bibd+1)                  and
        2*k == v+r_bibd-1                         and
        4*l == -2*v + 6*k -v_bibd -k_bibd         and
        hadamard_matrix(r_bibd+1, existence=True) and
        balanced_incomplete_block_design(v_bibd, k_bibd, existence = True)):
        from sage.graphs.generators.families import GoethalsSeidelGraph
        return [GoethalsSeidelGraph, k_bibd, r_bibd]

@cached_function
def is_NOodd(int v,int k,int l,int mu):
    r"""
    Test whether some NO^e(2n+1,q) graph is `(v,k,\lambda,\mu)`-strongly regular.

    Here `q>2`, for in the case `q=2` this graph is complete. For more
    information, see
    :func:`sage.graphs.graph_generators.GraphGenerators.NonisotropicOrthogonalPolarGraph`
    and Sect. 7.C of [BvL84]_.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_NOodd
        sage: t = is_NOodd(120, 51, 18, 24); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 4, '-')
        sage: g = t[0](*t[1:]); g
        NO^-(5, 4): Graph on 120 vertices
        sage: g.is_strongly_regular(parameters=True)
        (120, 51, 18, 24)

    TESTS:

    All of ``NO^+(2m+1,q)`` and ``NO^-(2m+1,q)`` appear::

        sage: t = is_NOodd(120, 51, 18, 24); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 4, '-')
        sage: t = is_NOodd(136, 75, 42, 40); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 4, '+')
        sage: t=is_NOodd(378, 260, 178, 180); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 7, 3, '+')
        sage: t=is_NOodd(45, 32, 22, 24); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 3, '+')
        sage: t=is_NOodd(351, 224, 142, 144); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 7, 3, '-')
        sage: t = is_NOodd(325, 144, 68, 60); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 5, '+')
        sage: t = is_NOodd(300, 104, 28, 40); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 5, '-')
        sage: t = is_NOodd(5,5,5,5); t
    """
    cdef int n, q
    r,s = eigenvalues(v,k,l,mu) # -eq^(n-1)-1 and eq^(n-1)(q-2)-1; q=3 is special case
    if r is None:
        return
    r += 1
    s += 1
    if abs(r)>abs(s):
        (r,s) = (s,r) # r=-eq^(n-1) s= eq^(n-1)(q-2)
    q = 2 - s/r
    p, t = is_prime_power(q, get_data=True)
    pp, kk = is_prime_power(abs(r), get_data=True)
    if p == pp and t != 0:
        n  = kk/t + 1
        e = 1 if v  == (q**n)*(q**n+1)/2 else -1
        if (v  == (q**n)*(q**n+e)/2                 and
            k  == (q**n-e)*(q**(n-1)+e)             and
            l  == 2*(q**(2*n-2)-1)+e*q**(n-1)*(q-1) and
            mu == 2*q**(n-1)*(q**(n-1)+e)):
            from sage.graphs.generators.classical_geometries import NonisotropicOrthogonalPolarGraph
            return (NonisotropicOrthogonalPolarGraph, 2*n+1, q, '+' if e==1 else '-')

@cached_function
def is_NOperp_F5(int v,int k,int l,int mu):
    r"""
    Test whether some NO^e,perp(2n+1,5) graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see
    :func:`sage.graphs.graph_generators.GraphGenerators.NonisotropicOrthogonalPolarGraph`
    and Sect. 7.D of [BvL84]_.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_NOperp_F5
        sage: t = is_NOperp_F5(10, 3, 0, 1); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 3, 5, '-', 1)
        sage: g = t[0](*t[1:]); g
        NO^-,perp(3, 5): Graph on 10 vertices
        sage: g.is_strongly_regular(parameters=True)
        (10, 3, 0, 1)

    TESTS:

    All of ``NO^+,perp(2m+1,5)`` and ``NO^-,perp(2m+1,5)`` appear::

        sage: t = is_NOperp_F5(325, 60, 15, 10); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 5, '+', 1)
        sage: t = is_NOperp_F5(300, 65, 10, 15); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 5, 5, '-', 1)
        sage: t = is_NOperp_F5(5,5,5,5); t
    """
    cdef int n
    r,s = eigenvalues(v,k,l,mu) # 2*e*5**(n-1), -e*5**(n-1); note exceptional case n=1
    if r is None:
        return
    if abs(r)<abs(s):
        (r,s) = (s,r)
    e = 1 if s<0 else -1
    p, n = is_prime_power(abs(s), get_data=True)
    if (5 == p and n != 0) or (abs(r)==2 and abs(s)==1):
        n += 1
        if (v  == (5**n)*(5**n+e)/2           and
            k  == (5**n-e)*5**(n-1)/2         and
            l  == 5**(n-1)*(5**(n-1)+e)/2     and
            mu == 5**(n-1)*(5**(n-1)-e)/2):
            from sage.graphs.generators.classical_geometries import NonisotropicOrthogonalPolarGraph
            return (NonisotropicOrthogonalPolarGraph, 2*n+1, 5, '+' if e==1 else '-', 1)

@cached_function
def is_NO_F2(int v,int k,int l,int mu):
    r"""
    Test whether some NO^e,perp(2n,2) graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see
    :func:`sage.graphs.graph_generators.GraphGenerators.NonisotropicOrthogonalPolarGraph`.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_NO_F2
        sage: t = is_NO_F2(10, 3, 0, 1); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 4, 2, '-')
        sage: g = t[0](*t[1:]); g
        NO^-(4, 2): Graph on 10 vertices
        sage: g.is_strongly_regular(parameters=True)
        (10, 3, 0, 1)

    TESTS:

    All of ``NO^+(2m,2)`` and ``NO^-(2m,2)`` appear::

        sage: t = is_NO_F2(36, 15, 6, 6); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 6, 2, '-')
        sage: t = is_NO_F2(28, 15, 6, 10); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 6, 2, '+')
        sage: t = is_NO_F2(5,5,5,5); t
    """
    cdef int n, e, p
    p, n = is_prime_power(k+1, get_data=True) # k+1==2**(2*n-2)
    if 2 == p and n != 0 and n % 2 == 0:
        n = (n+2)/2
        e = (2**(2*n-1)-v)/2**(n-1)
        if (abs(e) == 1                           and
            v  == 2**(2*n-1)-e*2**(n-1)           and
            k  == 2**(2*n-2)-1                    and
            l  == 2**(2*n-3)-2                    and
            mu == 2**(2*n-3)+e*2**(n-2)):
            from sage.graphs.generators.classical_geometries import NonisotropicOrthogonalPolarGraph
            return (NonisotropicOrthogonalPolarGraph, 2*n, 2, '+' if e==1 else '-')

@cached_function
def is_NO_F3(int v,int k,int l,int mu):
    r"""
    Test whether some NO^e,perp(2n,3) graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see
    :func:`sage.graphs.graph_generators.GraphGenerators.NonisotropicOrthogonalPolarGraph`.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_NO_F3
        sage: t = is_NO_F3(15, 6, 1, 3); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 4, 3, '-')
        sage: g = t[0](*t[1:]); g
        NO^-(4, 3): Graph on 15 vertices
        sage: g.is_strongly_regular(parameters=True)
        (15, 6, 1, 3)

    TESTS:

    All of ``NO^+(2m,3)`` and ``NO^-(2m,3)`` appear::

        sage: t = is_NO_F3(126, 45, 12, 18); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 6, 3, '-')
        sage: t = is_NO_F3(117, 36, 15, 9); t
        (<function NonisotropicOrthogonalPolarGraph at ...>, 6, 3, '+')
        sage: t = is_NO_F3(5,5,5,5); t
    """
    cdef int n, e, p
    r,s = eigenvalues(v,k,l,mu) # e*3**(n-1), -e*3**(n-2)
    if r is None:
        return
    if abs(r)<abs(s):
        (r,s) = (s,r)
    e = 1 if r>0 else -1
    p, n = is_prime_power(abs(r), get_data=True)
    if (3 == p and n != 0):
        n += 1
        if (v  == 3**(n-1)*(3**n-e)/2           and
            k  == 3**(n-1)*(3**(n-1)-e)/2           and
            l  == 3**(n-2)*(3**(n-1)+e)/2           and
            mu == 3**(n-1)*(3**(n-2)-e)/2):
            from sage.graphs.generators.classical_geometries import NonisotropicOrthogonalPolarGraph
            return (NonisotropicOrthogonalPolarGraph, 2*n, 3, '+' if e==1 else '-')

@cached_function
def is_NU(int v,int k,int l,int mu):
    r"""
    Test whether some NU(n,q)-graph, is `(v,k,\lambda,\mu)`-strongly regular.

    Note that n>2; for n=2 there is no s.r.g. For more information, see
    :func:`sage.graphs.graph_generators.GraphGenerators.NonisotropicUnitaryPolarGraph`
    and series C14 in [Hu75]_.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_NU
        sage: t = is_NU(40, 27, 18, 18); t
        (<function NonisotropicUnitaryPolarGraph at ...>, 4, 2)
        sage: g = t[0](*t[1:]); g
        NU(4, 2): Graph on 40 vertices
        sage: g.is_strongly_regular(parameters=True)
        (40, 27, 18, 18)

    TESTS::

        sage: t = is_NU(176, 135, 102, 108); t
        (<function NonisotropicUnitaryPolarGraph at ...>, 5, 2)
        sage: t = is_NU(540, 224, 88, 96); t
        (<function NonisotropicUnitaryPolarGraph at ...>, 4, 3)
        sage: t = is_NU(208, 75, 30, 25); t
        (<function NonisotropicUnitaryPolarGraph at ...>, 3, 4)
        sage: t = is_NU(5,5,5,5); t
    """
    cdef int n, q, e               # special cases: n=3 or q=2
    r,s = eigenvalues(v,k,l,mu) #r,s = eq^{n-2} - 1, -e(q^2-q-1)q^{n-3} - 1, e=(-1)^n
    if r is None:
        return
    r += 1
    s += 1
    if abs(r)>abs(s):
        (r,s) = (s,r)
    p, t = is_prime_power(abs(r), get_data=True)
    if p==2: # it can be that q=2, then we'd have r>s now
        pp, kk = is_prime_power(abs(s), get_data=True)
        if pp==2 and kk>0:
            (r,s) = (s,r)
            p, t = is_prime_power(abs(r), get_data=True)
    if r==1:
        return
    kr = k/(r-1) # eq^{n-1}+1
    e = 1 if kr>0 else -1
    q = (kr-1)/r
    pp, kk = is_prime_power(q, get_data=True)
    if p == pp and kk != 0:
        n  = t/kk + 2
        if (v  == q**(n-1)*(q**n - e)/(q + 1)               and
            k  == (q**(n-1) + e)*(q**(n-2) - e)             and
            l  == q**(2*n-5)*(q+1) - e*q**(n-2)*(q-1) - 2  and
            mu == q**(n-3)*(q + 1)*(q**(n-2) - e)):
            from sage.graphs.generators.classical_geometries import NonisotropicUnitaryPolarGraph
            return (NonisotropicUnitaryPolarGraph, n, q)

@cached_function
def is_polhill(int v,int k,int l,int mu):
    r"""
    Test whether some graph from [Polhill09]_ is `(1024,k,\lambda,\mu)`-strongly regular.

    .. NOTE::

        This function does not actually explore *all* strongly regular graphs
        produced in [Polhill09]_, but only those on 1024 vertices.

        John Polhill offered his help if we attempt to write a code to guess,
        given `(v,k,\lambda,\mu)`, which of his construction must be applied to
        find the graph.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if the
    parameters match, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_polhill
        sage: t = is_polhill(1024, 231,  38,  56); t
        [<cyfunction is_polhill.<locals>.<lambda> at ...>]
        sage: g = t[0](*t[1:]); g                    # not tested (too long)
        Graph on 1024 vertices
        sage: g.is_strongly_regular(parameters=True) # not tested (too long)
        (1024, 231, 38, 56)
        sage: t = is_polhill(1024, 264,  56,  72); t
        [<cyfunction is_polhill.<locals>.<lambda> at ...>]
        sage: t = is_polhill(1024, 297,  76,  90); t
        [<cyfunction is_polhill.<locals>.<lambda> at ...>]
        sage: t = is_polhill(1024, 330,  98, 110); t
        [<cyfunction is_polhill.<locals>.<lambda> at ...>]
        sage: t = is_polhill(1024, 462, 206, 210); t
        [<cyfunction is_polhill.<locals>.<lambda> at ...>]

    REFERENCE:

    .. [Polhill09] J. Polhill,
       Negative Latin square type partial difference sets and
       amorphic association schemes with Galois rings,
       Journal of Combinatorial Designs 17, no. 3 (2009): 266-282.
       http://onlinelibrary.wiley.com/doi/10.1002/jcd.20206/abstract
    """
    if (v,k,l,mu) not in [(1024, 231,  38,  56),
                          (1024, 264,  56,  72),
                          (1024, 297,  76,  90),
                          (1024, 330,  98, 110),
                          (1024, 462, 206, 210)]:
        return

    from itertools import product
    from sage.categories.cartesian_product import cartesian_product
    from sage.rings.finite_rings.integer_mod_ring import IntegerModRing
    from copy import copy

    def additive_cayley(vertices):
        g = Graph()
        g.add_vertices(vertices[0].parent())
        edges = [(x,x+vv)
                 for vv in set(vertices)
                 for x in g]
        g.add_edges(edges)
        g.relabel()
        return g

    # D is a Partial Difference Set of (Z4)^2, see section 2.
    G = cartesian_product([IntegerModRing(4),IntegerModRing(4)])
    D = [
        [(2,0),(0,1),(0,3),(1,1),(3,3)],
        [(1,0),(3,0),(0,2),(1,3),(3,1)],
        [(1,2),(3,2),(2,1),(2,3),(2,2)]
        ]
    D = [map(G,x) for x in D]

    # The K_i are hyperplanes partitionning the nonzero elements of
    # GF(2^s)^2. See section 6.
    s = 3
    G1 = GF(2**s,'x')
    Gp = cartesian_product([G1,G1])
    K = [Gp((x,1)) for x in G1]+[Gp((1,0))]
    K = [[x for x in Gp if x[0]*uu+x[1]*vv == 0] for (uu,vv) in K]

    # We now define the P_{i,j}. see section 6.

    P = {}
    P[0,1] = range((-1) + 1                  , 2**(s-2)+1)
    P[1,1] = range((-1) + 2**(s-2)+2         , 2**(s-1)+1)
    P[2,1] = range((-1) + 2**(s-1)+2         , 2**(s-1)+2**(s-2)+1)
    P[3,1] = range((-1) + 2**(s-1)+2**(s-2)+2, 2**(s)+1)

    P[0,2] = range((-1) + 2**(s-2)+2         , 2**(s-1)+2)
    P[1,2] = range((-1) + 2**(s-1)+3         , 2**(s-1)+2**(s-2)+2)
    P[2,2] = range((-1) + 2**(s-1)+2**(s-2)+3, 2**(s)+1) + [0]
    P[3,2] = range((-1) + 2                  , 2**(s-2)+1)

    P[0,3] = range((-1) + 2**(s-1)+3         , 2**(s-1)+2**(s-2)+3)
    P[1,3] = range((-1) + 2**(s-1)+2**(s-2)+4, 2**(s)+1) + [0,1]
    P[2,3] = range((-1) + 3                  , 2**(s-2)+2)
    P[3,3] = range((-1) + 2**(s-2)+3         , 2**(s-1)+2)

    P[0,4] = range((-1) + 2**(s-1)+2**(s-2)+4, 2**(s)+1)
    P[1,4] = range((-1) + 3                  , 2**(s-2)+1) + [2**(s-1)+1,2**(s-1)+2**(s-2)+2]
    P[2,4] = range((-1) + 2**(s-2)+3         , 2**(s-1)+1) + [2**(s-1)+2**(s-2)+1,1]
    P[3,4] = range((-1) + 2**(s-1)+3         , 2**(s-1)+2**(s-2)+1) + [2**(s-2)+1,0]

    R = {x:copy(P[x]) for x in P}

    for x in P:
        P[x] = [K[i] for i in P[x]]
        P[x] = set(sum(P[x],[])).difference([Gp((0,0))])

    P[1,4].add(Gp((0,0)))
    P[2,4].add(Gp((0,0)))
    P[3,4].add(Gp((0,0)))

    # We now define the R_{i,j}. see *end* of section 6.

    R[0,3] = range((-1) + 2**(s-1)+3         , 2**(s-1)+2**(s-2)+2)
    R[1,3] = range((-1) + 2**(s-1)+2**(s-2)+4, 2**(s)+1) + [0,1,2**(s-1)+2**(s-2)+2]
    R[0,4] = range((-1) + 2**(s-1)+2**(s-2)+4, 2**(s)+1) + [2**(s-1)+2**(s-2)+2]
    R[1,4] = range((-1) + 3                  , 2**(s-2)+1) + [2**(s-1)+1]

    for x in R:
        R[x] = [K[i] for i in R[x]]
        R[x] = set(sum(R[x],[])).difference([Gp((0,0))])

    R[1,3].add(Gp((0,0)))
    R[2,4].add(Gp((0,0)))
    R[3,4].add(Gp((0,0)))

    # Dabcd = Da, Db, Dc, Dd (cf. p273)
    # D1234 = D1, D2, D3, D4 (cf. p276)
    Dabcd = []
    D1234 = []

    Gprod = cartesian_product([G,Gp])
    for DD,PQ in [(Dabcd,P), (D1234,R)]:
        for i in range(1,5):
            Dtmp = [product([G.zero()],PQ[0,i]),
                    product(D[0],PQ[1,i]),
                    product(D[1],PQ[2,i]),
                    product(D[2],PQ[3,i])]
            Dtmp = map(set,Dtmp)
            Dtmp = map(Gprod,sum(map(list,Dtmp),[]))
            DD.append(Dtmp)

    # Now that we have the data, we can return the graphs.
    if k == 231:
        return [lambda :additive_cayley(Dabcd[0])]
    if k == 264:
        return [lambda :additive_cayley(D1234[2])]
    if k == 297:
        return [lambda :additive_cayley(D1234[0]+D1234[1]+D1234[2]).complement()]
    if k == 330:
        return [lambda :additive_cayley(Dabcd[0]+Dabcd[1]+Dabcd[2]).complement()]
    if k == 462:
        return [lambda :additive_cayley(Dabcd[0]+Dabcd[1])]

def is_RSHCD(int v,int k,int l,int mu):
    r"""
    Test whether some RSHCD graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see :func:`SRG_from_RSHCD`.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_RSHCD
        sage: t = is_RSHCD(64,27,10,12); t
        [<built-in function SRG_from_RSHCD>, 64, 27, 10, 12]
        sage: g = t[0](*t[1:]); g
        Graph on 64 vertices
        sage: g.is_strongly_regular(parameters=True)
        (64, 27, 10, 12)

    """
    if SRG_from_RSHCD(v,k,l,mu,existence=True):
        return [SRG_from_RSHCD,v,k,l,mu]

def SRG_from_RSHCD(v,k,l,mu, existence=False,check=True):
    r"""
    Return a `(v,k,l,mu)`-strongly regular graph from a RSHCD

    This construction appears in 8.D of [BvL84]_. For more information, see
    :func:`~sage.combinat.matrices.hadamard_matrix.regular_symmetric_hadamard_matrix_with_constant_diagonal`.

    INPUT:

    - ``v,k,l,mu`` (integers)

    - ``existence`` (boolean) -- whether to return a graph or to test if Sage
      can build such a graph.

    - ``check`` (boolean) -- whether to check that output is correct before
      returning it. As this is expected to be useless (but we are cautious
      guys), you may want to disable it whenever you want speed. Set to ``True``
      by default.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import SRG_from_RSHCD
        sage: SRG_from_RSHCD(784, 0, 14, 38, existence=True)
        False
        sage: SRG_from_RSHCD(784, 377, 180, 182, existence=True)
        True
        sage: SRG_from_RSHCD(144, 65, 28, 30)
        Graph on 144 vertices

    TESTS::

        sage: SRG_from_RSHCD(784, 0, 14, 38)
        Traceback (most recent call last):
        ...
        ValueError: I do not know how to build a (784, 0, 14, 38)-SRG from a RSHCD

    """
    from sage.combinat.matrices.hadamard_matrix import regular_symmetric_hadamard_matrix_with_constant_diagonal
    sgn = lambda x: 1 if x>=0 else -1
    n = v
    a = (n-4*mu)//2
    e = 2*k - n + 1 + a
    t = abs(a//2)

    if (e**2 == 1              and
        k == (n-1-a+e)/2       and
        l == (n-2*a)/4 - (1-e) and
        mu== (n-2*a)/4         and
        regular_symmetric_hadamard_matrix_with_constant_diagonal(n,sgn(a)*e,existence=True)):
        if existence:
            return True
        from sage.matrix.constructor import identity_matrix as I
        from sage.matrix.constructor import ones_matrix     as J

        H = regular_symmetric_hadamard_matrix_with_constant_diagonal(n,sgn(a)*e)
        if list(H.column(0)[1:]).count(1) == k:
            H = -H
        G = Graph((J(n)-I(n)-H+H[0,0]*I(n))/2,loops=False,multiedges=False,format="adjacency_matrix")
        if check:
            assert G.is_strongly_regular(parameters=True) == (v,k,l,mu)
        return G

    if existence:
        return False
    raise ValueError("I do not know how to build a {}-SRG from a RSHCD".format((v,k,l,mu)))

@cached_function
def is_unitary_polar(int v,int k,int l,int mu):
    r"""
    Test whether some Unitary Polar graph is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see http://www.win.tue.nl/~aeb/graphs/srghub.html.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_unitary_polar
        sage: t = is_unitary_polar(45, 12, 3, 3); t
        (<function UnitaryPolarGraph at ...>, 4, 2)
        sage: g = t[0](*t[1:]); g
        Unitary Polar Graph U(4, 2); GQ(4, 2): Graph on 45 vertices
        sage: g.is_strongly_regular(parameters=True)
        (45, 12, 3, 3)

        sage: t = is_unitary_polar(5,5,5,5); t

    TESTS:

    All the ``U(n,q)`` appear::

        sage: t = is_unitary_polar(45, 12, 3, 3); t
        (<function UnitaryPolarGraph at ...>, 4, 2)
        sage: t = is_unitary_polar(165, 36, 3, 9); t
        (<function UnitaryPolarGraph at ...>, 5, 2)
        sage: t = is_unitary_polar(693, 180, 51, 45); t
        (<function UnitaryPolarGraph at ...>, 6, 2)
        sage: t = is_unitary_polar(1105, 80, 15, 5); t
        (<function UnitaryPolarGraph at ...>, 4, 4)
    """
    r,s = eigenvalues(v,k,l,mu)
    if r is None:
        return
    q = k/mu
    if q*mu != k or q < 2:
        return
    p,t = is_prime_power(q, get_data=True)
    if p**t != q or t % 2 != 0:
        return
    # at this point we know that we should have U(n,q) for some n and q=p^t, t even
    if r > 0:
        q_pow_d_minus_one = r+1
    else:
        q_pow_d_minus_one = -s-1
    ppp,ttt = is_prime_power(q_pow_d_minus_one, get_data=True)
    d = ttt/t + 1
    if ppp != p or (d-1)*t != ttt:
        return
    t /= 2
    # U(2d+1,q); write q^(1/2) as p^t
    if (v == (q**d - 1)*((q**d)*p**t + 1)/(q - 1)               and
        k == q*(q**(d-1) - 1)*((q**d)/(p**t) + 1)/(q - 1)       and
        l == q*q*(q**(d-2)-1)*((q**(d-1))/(p**t) + 1)/(q - 1) + q - 1):
        from sage.graphs.generators.classical_geometries import UnitaryPolarGraph
        return (UnitaryPolarGraph, 2*d+1, p**t)

    # U(2d,q);
    if (v == (q**d - 1)*((q**d)/(p**t) + 1)/(q - 1)             and
        k == q*(q**(d-1) - 1)*((q**(d-1))/(p**t) + 1)/(q - 1)   and
        l == q*q*(q**(d-2)-1)*((q**(d-2))/(p**t) + 1)/(q - 1) + q - 1):
        from sage.graphs.generators.classical_geometries import UnitaryPolarGraph
        return (UnitaryPolarGraph, 2*d, p**t)

@cached_function
def is_unitary_dual_polar(int v,int k,int l,int mu):
    r"""
    Test whether some Unitary Dual Polar graph is `(v,k,\lambda,\mu)`-strongly regular.

    This must be the U_5(q) on totally isotropic lines.
    For more information, see http://www.win.tue.nl/~aeb/graphs/srghub.html.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_unitary_dual_polar
        sage: t = is_unitary_dual_polar(297, 40, 7, 5); t
        (<function UnitaryDualPolarGraph at ...>, 5, 2)
        sage: g = t[0](*t[1:]); g
        Unitary Dual Polar Graph DU(5, 2); GQ(8, 4): Graph on 297 vertices
        sage: g.is_strongly_regular(parameters=True)
        (297, 40, 7, 5)
        sage: t = is_unitary_dual_polar(5,5,5,5); t

    TESTS::

        sage: is_unitary_dual_polar(6832, 270, 26, 10)
        (<function UnitaryDualPolarGraph at ...>, 5, 3)
    """
    r,s = eigenvalues(v,k,l,mu)
    if r is None:
        return
    q = mu - 1
    if q < 2:
        return
    p,t = is_prime_power(q, get_data=True)
    if p**t != q or t % 2 != 0:
        return
    if (r < 0 and q != -r - 1) or (s < 0 and q != -s - 1):
       return
    t /= 2
    # we have correct mu, negative eigenvalue, and q=p^(2t)
    if (v == (q**2*p**t + 1)*(q*p**t + 1)  and
        k == q*p**t*(q + 1)                and
        l == k - 1 - q**2*p**t):
        from sage.graphs.generators.classical_geometries import UnitaryDualPolarGraph
        return (UnitaryDualPolarGraph, 5, p**t)

@cached_function
def is_GQqmqp(int v,int k,int l,int mu):
    r"""
    Test whether some `GQ(q-1,q+1)` or `GQ(q+1,q-1)`-graph is `(v,k,\lambda,\mu)`-srg.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_GQqmqp
        sage: t = is_GQqmqp(27,10,1,5); t
        (<function AhrensSzekeresGeneralizedQuadrangleGraph at ...>, 3, False)
        sage: g = t[0](*t[1:]); g
        AS(3); GQ(2, 4): Graph on 27 vertices
        sage: t = is_GQqmqp(45,12,3,3); t
        (<function AhrensSzekeresGeneralizedQuadrangleGraph at ...>, 3, True)
        sage: g = t[0](*t[1:]); g
        AS(3)*; GQ(4, 2): Graph on 45 vertices
        sage: g.is_strongly_regular(parameters=True)
        (45, 12, 3, 3)
        sage: t = is_GQqmqp(16,6,2,2); t
        (<function T2starGeneralizedQuadrangleGraph at ...>, 2, True)
        sage: g = t[0](*t[1:]); g
        T2*(O,2)*; GQ(3, 1): Graph on 16 vertices
        sage: g.is_strongly_regular(parameters=True)
        (16, 6, 2, 2)
        sage: t = is_GQqmqp(64,18,2,6); t
        (<function T2starGeneralizedQuadrangleGraph at ...>, 4, False)
        sage: g = t[0](*t[1:]); g
        T2*(O,4); GQ(3, 5): Graph on 64 vertices
        sage: g.is_strongly_regular(parameters=True)
        (64, 18, 2, 6)

    TESTS::

        sage: (S,T)=(127,129)
        sage: t = is_GQqmqp((S+1)*(S*T+1), S*(T+1), S-1, T+1); t
        (<function T2starGeneralizedQuadrangleGraph at ...>, 128, False)
        sage: (S,T)=(129,127)
        sage: t = is_GQqmqp((S+1)*(S*T+1), S*(T+1), S-1, T+1); t
        (<function T2starGeneralizedQuadrangleGraph at ...>, 128, True)
        sage: (S,T)=(124,126)
        sage: t = is_GQqmqp((S+1)*(S*T+1), S*(T+1), S-1, T+1); t
        (<function AhrensSzekeresGeneralizedQuadrangleGraph at ...>, 125, False)
        sage: (S,T)=(126,124)
        sage: t = is_GQqmqp((S+1)*(S*T+1), S*(T+1), S-1, T+1); t
        (<function AhrensSzekeresGeneralizedQuadrangleGraph at ...>, 125, True)
        sage: t = is_GQqmqp(5,5,5,5); t
    """
    # do we have GQ(s,t)? we must have mu=t+1, s=l+1,
    # v=(s+1)(st+1), k=s(t+1)
    S=l+1
    T=mu-1
    q = (S+T)//2
    p, w = is_prime_power(q, get_data=True)
    if (v == (S+1)*(S*T+1)      and
        k == S*(T+1)            and
        q == p**w               and
        (S+T)/2 == q):
        if p % 2 == 0:
            from sage.graphs.generators.classical_geometries\
                    import T2starGeneralizedQuadrangleGraph as F
        else:
            from sage.graphs.generators.classical_geometries\
                    import AhrensSzekeresGeneralizedQuadrangleGraph as F
        if (S,T) == (q-1, q+1):
            return (F, q, False)
        elif (S,T) == (q+1, q-1):
            return (F, q, True)

@cached_function
def is_twograph_descendant_of_srg(int v, int k0, int l, int mu):
    r"""
    Test whether some descendant graph of an s.r.g. is `(v,k_0,\lambda,\mu)`-s.r.g.

    We check whether there can exist `(v+1,k,\lambda^*,\mu^*)`-s.r.g. `G` so
    that ``self`` is a descendant graph of the regular two-graph specified
    by `G`.
    Specifically, we must have that `v+1=2(2k-\lambda^*-\mu^*)`, and
    `k_0=2(k-\mu^*)`, `\lambda=k+\lambda^*-2\mu^*`, `\mu=k-\mu^*`, which give 2
    independent linear conditions, say `k-\mu^*=\mu` and
    `\lambda^*-\mu^*=\lambda-\mu`.  Further, there is a quadratic relation
    `2 k^2-(v+1+4 \mu) k+ 2 v \mu=0`.

    If we can contruct such `G` then we return a function to build a
    `(v,k_0,\lambda,\mu)`-s.r.g.  For more information,
    see 10.3 in http://www.win.tue.nl/~aeb/2WF02/spectra.pdf

    INPUT:

    - ``v,k0,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if one
    exists and is known, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_twograph_descendant_of_srg
        sage: t = is_twograph_descendant_of_srg(27, 10, 1, 5); t
        (<cyfunction is_twograph_descendant_of_srg.<locals>.la at...
        sage: g = t[0](*t[1:]); g
        descendant of complement(Johnson graph with parameters 8,2) at {5, 7}: Graph on 27 vertices
        sage: g.is_strongly_regular(parameters=True)
        (27, 10, 1, 5)
        sage: t = is_twograph_descendant_of_srg(5,5,5,5); t

    TESTS::

        sage: graphs.strongly_regular_graph(279, 150, 85, 75, existence=True)
        True
        sage: graphs.strongly_regular_graph(279, 150, 85, 75).is_strongly_regular(parameters=True) # optional - gap_packages internet
        (279, 150, 85, 75)
    """
    cdef int b, k, s
    if k0 != 2*mu or v % 2 == 0:
        return
    b = v+1+4*mu
    D = sqrt(b**2-16*v*mu)
    if int(D)==D:
        for kf in [(-D+b)/4, (D+b)/4]:
            k = int(kf)
            if k == kf and \
                strongly_regular_graph(v+1, k, l - 2*mu + k , k - mu,  existence=True):
                def la(vv):
                    from sage.combinat.designs.twographs import twograph_descendant
                    g = strongly_regular_graph(vv, k, l - 2*mu + k)
                    return twograph_descendant(g, g.vertex_iterator().next(), name=True)
                return(la, v+1)
    return

@cached_function
def is_taylor_twograph_srg(int v,int k,int l,int mu):
    r"""
    Test whether some Taylor two-graph SRG is `(v,k,\lambda,\mu)`-strongly regular.

    For more information, see §7E of [BvL84]_.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph
    :func:`TaylorTwographSRG
    <sage.graphs.graph_generators.GraphGenerators.TaylorTwographSRG>` if the
    parameters match, and ``None`` otherwise.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import is_taylor_twograph_srg
        sage: t = is_taylor_twograph_srg(28, 15, 6, 10); t
        (<function TaylorTwographSRG at ...>, 3)
        sage: g = t[0](*t[1:]); g
        Taylor two-graph SRG: Graph on 28 vertices
        sage: g.is_strongly_regular(parameters=True)
        (28, 15, 6, 10)
        sage: t = is_taylor_twograph_srg(5,5,5,5); t

    TESTS::

        sage: is_taylor_twograph_srg(730, 369, 168, 205)
        (<function TaylorTwographSRG at ...>, 9)

    """
    r,s = eigenvalues(v,k,l,mu)
    if r is None:
        return
    p,t = is_prime_power(v-1, get_data=True)
    if p**t+1 != v or t % 3 != 0 or p % 2 == 0:
        return
    q = p**(t//3)
    if (k, l, mu) == (q*(q**2+1)/2, (q**2+3)*(q-1)/4, (q**2+1)*(q+1)/4):
        from sage.graphs.generators.classical_geometries import TaylorTwographSRG
        return (TaylorTwographSRG, q)
    return

def is_switch_skewhad(int v, int k, int l, int mu):
    r"""
    Test whether some `switch skewhad^2+*` is `(v,k,\lambda,\mu)`-strongly regular.

    The `switch skewhad^2+*` graphs appear on `Andries Brouwer's database
    <http://www.win.tue.nl/~aeb/graphs/srg/srgtab.html>`__ and are built by
    adding an isolated vertex to the complement of
    :func:`~sage.graphs.graph_generators.GraphGenerators.SquaredSkewHadamardMatrixGraph`,
    and a :meth:`Seidel switching <Graph.seidel_switching>` a set of disjoint
    `n`-cocliques.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if the
    parameters match, and ``None`` otherwise.

    EXAMPLES::

        sage: graphs.strongly_regular_graph(226, 105, 48, 49)
        switch skewhad^2+*_4: Graph on 226 vertices

    TESTS::

        sage: from sage.graphs.strongly_regular_db import is_switch_skewhad
        sage: t = is_switch_skewhad(5,5,5,5); t

    """
    from sage.combinat.matrices.hadamard_matrix import skew_hadamard_matrix
    from sage.graphs.generators.families import SwitchedSquaredSkewHadamardMatrixGraph
    cdef int n
    r,s = eigenvalues(v,k,l,mu)
    if r is None:
        return
    if r<s:
        r,s = s,r
    n = -s // 2
    if  int(r) == 2*n-1         and \
        v == (4*n-1)**2 + 1     and \
        k == (4*n-1)*(2*n-1)    and \
        skew_hadamard_matrix(4*n, existence=True):
            return (SwitchedSquaredSkewHadamardMatrixGraph, n)

def is_switch_OA_srg(int v, int k, int l, int mu):
    r"""
    Test whether some *switch* `OA(k,n)+*` is `(v,k,\lambda,\mu)`-strongly regular.

    The "switch* `OA(k,n)+*` graphs appear on `Andries Brouwer's database
    <http://www.win.tue.nl/~aeb/graphs/srg/srgtab.html>`__ and are built by
    adding an isolated vertex to a
    :meth:`~sage.graphs.graph_generators.GraphGenerators.OrthogonalArrayBlockGraph`,
    and a :meth:`Seidel switching <Graph.seidel_switching>` a set of disjoint
    `n`-cocliques.

    INPUT:

    - ``v,k,l,mu`` (integers)

    OUTPUT:

    A tuple ``t`` such that ``t[0](*t[1:])`` builds the requested graph if the
    parameters match, and ``None`` otherwise.

    EXAMPLES::

        sage: graphs.strongly_regular_graph(170, 78, 35, 36) # indirect doctest
        Graph on 170 vertices

    TESTS::

        sage: from sage.graphs.strongly_regular_db import is_switch_OA_srg
        sage: t = is_switch_OA_srg(5,5,5,5); t
        sage: t = is_switch_OA_srg(170, 78, 35, 36);
        sage: t[0](*t[1:]).is_strongly_regular(parameters=True)
        (170, 78, 35, 36)
        sage: t = is_switch_OA_srg(290, 136,  63,  64);
        sage: t[0](*t[1:]).is_strongly_regular(parameters=True)
        (290, 136, 63, 64)
        sage: is_switch_OA_srg(626, 300, 143, 144)
        (<cyfunction is_switch_OA_srg.<locals>.switch_OA_srg at ..., 12, 25)
        sage: is_switch_OA_srg(842, 406, 195, 196)
        (<cyfunction is_switch_OA_srg.<locals>.switch_OA_srg at ..., 14, 29)

    """
    cdef int n_2_p_1 = v
    cdef int n = <int> floor(sqrt(n_2_p_1-1))

    if n*n != n_2_p_1-1: # is it a square?
        return None

    cdef int c = k/n
    if (k % n                            or
        l != c*c-1                       or
        k != 1+(c-1)*(c+1)+(n-c)*(n-c-1) or
        not orthogonal_array(c+1,n,existence=True,resolvable=True)):
        return None

    def switch_OA_srg(c,n):
        from itertools import izip
        OA = map(tuple,orthogonal_array(c+1,n,resolvable=True))
        g = Graph([OA,lambda x,y: any(xx==yy for xx,yy in izip(x,y))],loops=False)
        g.add_vertex(0)
        g.seidel_switching(OA[:c*n])
        return g

    return (switch_OA_srg,c,n)

cdef eigenvalues(int v,int k,int l,int mu):
    r"""
    Return the eigenvalues of a (v,k,l,mu)-strongly regular graph.

    If the set of parameters is not feasible, or if they correspond to a
    conference graph, the function returns ``(None,None)``.

    INPUT:

    - ``v,k,l,mu`` (integers)

    """
    # See 1.3.1 of [Distance-regular graphs]
    b = (mu-l)
    c = (mu-k)
    D = b**2-4*c
    if not is_square(D):
        return [None,None]
    return [(-b+sqrt(D))/2.0,
            (-b-sqrt(D))/2.0]


cpdef latin_squares_graph_parameters(int v,int k, int l,int mu):
    r"""
    Check whether (v,k,l,mu)-strongly regular graph has parameters of an `L_g(n)` s.r.g.

    Also known as pseudo-OA(n,g) case, i.e. s.r.g. with parameters of an OA(n,g)-graph.
    Return g and n, if they exist. See Sect. 9.1 of [BH12]_ for details.

    INPUT:

    - ``v,k,l,mu`` -- (integers) parameters of the graph

    OUTPUT:

    - ``(g, n)`` -- parameters of an `L_g(n)` graph, or `None`

    TESTS::

        sage: from sage.graphs.strongly_regular_db import latin_squares_graph_parameters
        sage: latin_squares_graph_parameters(9,4,1,2)
        (2, 3)
        sage: latin_squares_graph_parameters(5,4,1,2)
    """
    cdef int g, n
    r,s = eigenvalues(v,k,l,mu)
    if r is None:
        return
    if r < s:
        r, s = s, r
    g = -s
    n = r+g
    if v==n**2 and k==g*(n-1) and l==(g-1)*(g-2)+n-2 and mu==g*(g-1):
        return g, n
    return

def _H_3_cayley_graph(L):
    r"""
    return the `L`-Cayley graph of the group `H_3` from Prop. 12 in [JK03]_.

    INPUT:

    - the list of words for the generating set in the format ["abc",...,"xyz"] for
      a,b,...,z being integers between 0 and 4.

    TESTS::

        sage: from sage.graphs.strongly_regular_db import _H_3_cayley_graph
        sage: _H_3_cayley_graph(["100","110","130","140","200","230","240","300"])
        Graph on 100 vertices
    """
    from sage.groups.free_group import FreeGroup
    from sage.groups.finitely_presented import FinitelyPresentedGroup
    G = FreeGroup('x,y,z')
    x,y,z = G.gens()
    rels = (x**5,y**5,z**4,x*y*x**(-1)*y**(-1),z*x*z**(-1)*x**(-2),z*y*z**(-1)*y**(-2))
    G = FinitelyPresentedGroup(G,rels)
    x,y,z = G.gens()
    H = G.as_permutation_group()
    L = map(lambda x:map(int,x),L)
    x,y,z=(H.gen(0),H.gen(1),H.gen(2))
    L = [H(x**xx*y**yy*z**zz) for xx,yy,zz in L]
    return Graph(H.cayley_graph(generators=L, simple=True))

def SRG_100_44_18_20():
    r"""
    Return a `(100, 44, 18, 20)`-strongly regular graph.

    This graph is built as a Cayley graph, using the construction for `\Delta_1`
    with group `H_3` presented in Table 8.1 of [JK03]_

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_100_44_18_20
        sage: G = SRG_100_44_18_20()                 # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (100, 44, 18, 20)

    REFERENCES:

    .. [JK03] L. K. Jørgensen, M. Klin, M.,
      Switching of edges in strongly regular graphs.
      I. A family of partial difference sets on 100 vertices,
      Electronic Journal of Combinatorics 10(1), 2003.
    """
    return _H_3_cayley_graph(["100","110","130","140","200","230","240","300",
             "310","320","400","410","420","440","041","111","221","231","241",
             "321","331","401","421","441","002","042","112","122","142","212",
             "232","242","322","342","033","113","143","223","303","333","343",
             "413","433","443"])

def SRG_100_45_20_20():
    r"""
    Return a `(100, 45, 20, 20)`-strongly regular graph.

    This graph is built as a Cayley graph, using the construction for `\Gamma_3`
    with group `H_3` presented in Table 8.1 of [JK03]_.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_100_45_20_20
        sage: G = SRG_100_45_20_20()              # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (100, 45, 20, 20)
    """
    return _H_3_cayley_graph(["120","140","200","210","201","401","411","321",
             "002","012","022","042","303","403","013","413","240","031","102",
             "323","300","231","132","133","310","141","142","233","340","241",
             "202","333","410","341","222","433","430","441","242","302","312",
             "322","332","442","143"])


def SRG_105_32_4_12():
    r"""
    Return a `(105, 32, 4, 12)`-strongly regular graph.

    The vertices are the flags of the projective plane of order 4. Two flags
    `(a,A)` and `(b,B)` are adjacent if the point `a` is on the line `B` or
    the point `b` is  on the line `A`, and `a \neq b`, `A \neq B`. See
    Theorem 2.7 in [GS70]_, and [Co06]_.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_105_32_4_12
        sage: G = SRG_105_32_4_12(); G
        Graph on 105 vertices
        sage: G.is_strongly_regular(parameters=True)
        (105, 32, 4, 12)

    REFERENCES:

    .. [GS70] J.-M. Goethals and J. J. Seidel,
       Strongly regular graphs derived from combinatorial designs,
       Can. J. Math. 22 (1970) 597-614.
       http://dx.doi.org/10.4153/CJM-1970-067-9

    .. [Co06] K. Coolsaet,
       The uniqueness of the strongly regular graph srg(105,32,4,12),
       Bull. Belg. Math. Soc. 12(2006), 707-718.
       http://projecteuclid.org/euclid.bbms/1136902608
    """
    from sage.combinat.designs.block_design import ProjectiveGeometryDesign
    P = ProjectiveGeometryDesign(2,1,GF(4,'a'))
    IG = P.incidence_graph().line_graph()
    a = IG.automorphism_group()
    h = a.stabilizer(a.domain()[0])
    o = filter(lambda x: len(x)==32, h.orbits())[0][0]
    e = a.orbit((a.domain()[0],o),action="OnSets")
    G = Graph()
    G.add_edges(e)
    return G

def SRG_120_77_52_44():
    r"""
    Return a `(120,77,52,44)`-strongly regular graph.

    To build this graph, we first build a `2-(21,7,12)` design, by removing two
    points from the :func:`~sage.combinat.designs.block_design.WittDesign` on 23
    points. We then build the intersection graph of blocks with intersection
    size 3.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_120_77_52_44
        sage: G = SRG_120_77_52_44()                 # optional - gap_packages
        sage: G.is_strongly_regular(parameters=True) # optional - gap_packages
        (120, 77, 52, 44)
    """
    from sage.combinat.designs.block_design import WittDesign
    from sage.combinat.designs.incidence_structures import IncidenceStructure
    W = WittDesign(23)
    H = IncidenceStructure([x for x in W if 22 not in x and 21 not in x])
    return H.intersection_graph(3)

def SRG_144_39_6_12():
    r"""
    Return a `(144,39,6,12)`-strongly regular graph.

    This graph is obtained as an orbit of length 2808 on sets of cardinality 2
    (among 2 such orbits) of the group `PGL_3(3)` acting on the (right) cosets of
    a subgroup of order 39.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_144_39_6_12
        sage: G = SRG_144_39_6_12()
        sage: G.is_strongly_regular(parameters=True)
        (144, 39, 6, 12)
    """

    from sage.libs.gap.libgap import libgap
    g=libgap.ProjectiveGeneralLinearGroup(3,3)
    ns=g.Normalizer(g.SylowSubgroup(13))
    G=g.Action(g.RightCosets(ns),libgap.OnRight)
    H=G.Stabilizer(1)
    for o in filter(lambda x: len(x)==39, H.Orbits()):
        h = Graph()
        h.add_edges(G.Orbit([1,o[0]],libgap.OnSets))
        if h.is_strongly_regular():
            h.relabel()
            return h

def SRG_176_49_12_14():
    r"""
    Return a `(176,49,12,14)`-strongly regular graph.

    This graph is built from the symmetric Higman-Sims design. In
    [BrouwerPolarities82]_, it is explained that there exists an involution
    `\sigma` exchanging the points and blocks of the Higman-Sims design, such
    that each point is mapped on a block that contains it (i.e. `\sigma` is a
    'polarity with all universal points'). The graph is then built by making two
    vertices `u,v` adjacent whenever `v\in \sigma(u)`.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_176_49_12_14
        sage: G = SRG_176_49_12_14()                 # optional - gap_packages # long time
        sage: G.is_strongly_regular(parameters=True) # optional - gap_packages # long time
        (176, 49, 12, 14)

    REFERENCE:

    .. [BrouwerPolarities82] A. Brouwer,
       Polarities of G. Higman's symmetric design and a strongly regular graph on 176 vertices,
       Aequationes mathematicae 25, no. 1 (1982): 77-82.
    """
    from sage.combinat.designs.database import HigmanSimsDesign
    d = HigmanSimsDesign()
    g = d.incidence_graph(labels=True)
    ag=g.automorphism_group().conjugacy_classes_representatives()

    # Looking for an involution that maps a point of the design to one of the
    # blocks that contains it. It is called a polarity with only absolute
    # points in
    for aut in ag:
        try:
            0 in aut(0)
        except TypeError:
            continue
        if (aut.order() == 2 and
            all(i in aut(i) for i in d.ground_set())):
            g = Graph()
            g.add_edges((u,v) for u in d.ground_set() for v in aut(u))
            return g

def SRG_176_105_68_54():
    r"""
    Return a `(176, 105, 68, 54)`-strongly regular graph.

    To build this graph, we first build a `2-(22,7,16)` design, by removing one
    point from the :func:`~sage.combinat.designs.block_design.WittDesign` on 23
    points. We then build the intersection graph of blocks with intersection
    size 3.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_176_105_68_54
        sage: G = SRG_176_105_68_54()                # optional - gap_packages
        sage: G.is_strongly_regular(parameters=True) # optional - gap_packages
        (176, 105, 68, 54)
    """
    from sage.combinat.designs.block_design import WittDesign
    from sage.combinat.designs.incidence_structures import IncidenceStructure
    W = WittDesign(23)
    H = IncidenceStructure([x for x in W if 22 not in x])
    return H.intersection_graph(3)

def SRG_210_99_48_45():
    r"""
    Return a strongly regular graph with parameters `(210, 99, 48, 45)`

    This graph is from Example 4.2 in [KPRWZ10]_. One considers the action of
    the symmetric group `S_7` on the 210 digraphs isomorphic to the
    disjoint union of `K_1` and the circulant 6-vertex digraph
    ``digraphs.Circulant(6,[1,4])``. It has 16 orbitals; the package [COCO]_
    found a megring of them, explicitly described in [KPRWZ10]_, resulting in
    this graph.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_210_99_48_45
        sage: g=SRG_210_99_48_45()
        sage: g.is_strongly_regular(parameters=True)
        (210, 99, 48, 45)

    REFERENCES:

    .. [KPRWZ10] M. H. Klin, C. Pech, S. Reichard, A. Woldar, M. Zvi-Av,
       Examples of computer experimentation in algebraic combinatorics,
       ARS MATHEMATICA CONTEMPORANEA 3 (2010) 237–258
       http://amc-journal.eu/index.php/amc/article/viewFile/119/118

    .. [COCO] I. A. Faradjev and M. H. Klin,
       Computer package for computations with coherent configurations,
       Proc. ISSAC-91, ACM Press, Bonn, 1991, pages 219–223;
       code, by I.A.Faradjev (with contributions by A.E.Brouwer, D.V.Pasechnik)
       https://github.com/dimpase/coco

    """
    from sage.libs.gap.libgap import libgap
    from sage.combinat.permutation import Permutation
    def ekg(g0): # return arcs of the Cayley digraph of <g> on {g,g^4}
        g = Permutation(g0)
        return libgap.Set(map(lambda x: (x,g(x)), range(1,8))\
                        + map(lambda x: (x,g(g(g(g(x))))), range(1,8)))

    kd=map(ekg,
        [(7, 1, 2, 3, 4, 5), (7, 1, 3, 4, 5, 6),
        (7, 3, 4, 5, 6, 2), (7, 1, 4, 3, 5, 6),
        (7, 3, 1, 4, 5, 6), (7, 2, 4, 3, 5, 6),
        (7, 3, 2, 4, 5, 1), (7, 2, 4, 3, 5, 1)])
    s=libgap.SymmetricGroup(7)
    O=s.Orbit(kd[0],libgap.OnSetsTuples)
    sa=s.Action(O,libgap.OnSetsTuples)
    G=Graph()
    for g in kd[1:]:
        G.add_edges(libgap.Orbit(sa,[libgap.Position(O,kd[0]),\
                                     libgap.Position(O,g)],libgap.OnSets))
    return G

def SRG_243_110_37_60():
    r"""
    Return a `(243, 110, 37, 60)`-strongly regular graph.

    To build this graph, we consider the orthogonal complement of the
    :func:`~sage.coding.code_constructions.TernaryGolayCode`, which has 243
    points. On those points we define a graph, in which two points are adjacent
    when their hamming distance is equal to 9. This construction appears in
    [GS75]_.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_243_110_37_60
        sage: G = SRG_243_110_37_60()
        sage: G.is_strongly_regular(parameters=True)
        (243, 110, 37, 60)

    REFERENCE:

    .. [GS75] J.M. Goethals, and J. J. Seidel,
       The regular two-graph on 276 vertices,
       Discrete Mathematics 12, no. 2 (1975): 143-158.
       http://dx.doi.org/10.1016/0012-365X(75)90029-1
    """
    from sage.coding.code_constructions import TernaryGolayCode
    M = TernaryGolayCode().generator_matrix()
    V = list(M.right_kernel())
    return Graph([range(len(V)), lambda x,y:(V[x]-V[y]).hamming_weight() == 9 ])

def SRG_253_140_87_65():
    r"""
    Return a `(253, 140, 87, 65)`-strongly regular graph.

    To build this graph, we first build the
    :func:`~sage.combinat.designs.block_design.WittDesign` on 23 points which is
    a `2-(23,7,21)` design. We then build the intersection graph of blocks with
    intersection size 3.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_253_140_87_65
        sage: G = SRG_253_140_87_65()                # optional - gap_packages
        sage: G.is_strongly_regular(parameters=True) # optional - gap_packages
        (253, 140, 87, 65)
    """
    from sage.combinat.designs.block_design import WittDesign
    from sage.combinat.designs.incidence_structures import IncidenceStructure
    W = WittDesign(23)
    return W.intersection_graph(3)

def SRG_196_91_42_42():
    r"""
    Return a `(196,91,42,42)`-strongly regular graph.

    This strongly regular graph is built following the construction provided in
    Corollary 8.2.27 of [IS06]_.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import SRG_196_91_42_42
        sage: G = SRG_196_91_42_42()
        sage: G.is_strongly_regular(parameters=True)
        (196, 91, 42, 42)

    REFERENCE:

    .. [IS06] Y.J. Ionin, S. Shrikhande,
      Combinatorics of symmetric designs.
      Cambridge University Press, 2006.
    """
    from sage.rings.finite_rings.integer_mod_ring import IntegerModRing
    from sage.graphs.generators.intersection import IntersectionGraph
    k = 7
    G = IntegerModRing(91)
    A = map(G,{0, 10, 27, 28, 31, 43, 50})
    B = map(G,{0, 11, 20, 25, 49, 55, 57})
    H = map(G,[13*i for i in range(k)])
    U = map(frozenset,[[x+z for x in A] for z in G])
    V = map(frozenset,[[x+z for x in B] for z in G])
    W = map(frozenset,[[x+z for x in H] for z in G])
    G = IntersectionGraph(U+V+W)

    G.seidel_switching(U)

    G.add_edges((-1,x) for x in U)
    G.relabel()
    return G

def SRG_220_84_38_28():
    r"""
    Return a `(280, 135, 70, 60)`-strongly regular graph.

    This graph is obtained from the
    :meth:`~IncidenceStructure.intersection_graph` of a
    :func:`~sage.combinat.designs.database.BIBD_45_9_8`. This construction
    appears in VII.11.2 from [DesignHandbook]_

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_220_84_38_28
        sage: g=SRG_220_84_38_28()
        sage: g.is_strongly_regular(parameters=True)
        (220, 84, 38, 28)
    """
    from sage.combinat.designs.database import BIBD_45_9_8
    from sage.combinat.designs.incidence_structures import IncidenceStructure
    G = IncidenceStructure(BIBD_45_9_8()).intersection_graph(3)
    G.relabel()
    return G

def SRG_276_140_58_84():
    r"""
    Return a `(276, 140, 58, 84)`-strongly regular graph.

    The graph is built from from
    :meth:`~sage.graphs.graph_generators.GraphGenerators.McLaughlinGraph`, with
    an added isolated vertex. We then perform a
    :meth:`~Graph.seidel_switching` on a set of 28 disjoint 5-cliques, which
    exist by cf. [HT96]_.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_276_140_58_84
        sage: g=SRG_276_140_58_84()                  # long time # optional - gap_packages
        sage: g.is_strongly_regular(parameters=True) # long time # optional - gap_packages
        (276, 140, 58, 84)

    REFERENCE:

    .. [HT96] W. H. Haemers and V. D. Tonchev,
      Spreads in strongly regular graphs,
      Designs, Codes and Cryptography 8 (1996) 145-157.
    """
    g = McLaughlinGraph()
    C = [[ 0,  72,  87, 131, 136], [ 1,  35,  61, 102, 168], [ 2,  32,  97, 125, 197], [ 3,  22,  96, 103, 202],
         [ 4,  46,  74, 158, 229], [ 5,  83,  93, 242, 261], [ 6,  26,  81, 147, 176], [ 7,  42,  63, 119, 263],
         [ 8,  49,  64, 165, 227], [ 9,  70,  85, 208, 273], [10,  73,  92, 230, 268], [11,  54,  95, 184, 269],
         [12,  55,  62, 185, 205], [13,  51,  65, 162, 254], [14,  78,  88, 231, 274], [15,  40,  59, 117, 252],
         [16,  24,  71, 137, 171], [17,  39,  43, 132, 163], [18,  57,  79, 175, 271], [19,  68,  80, 217, 244],
         [20,  75,  98, 239, 267], [21,  33,  56, 113, 240], [23, 127, 152, 164, 172], [25, 101, 128, 183, 264],
         [27, 129, 154, 160, 201], [28, 126, 144, 161, 228], [29, 100, 133, 204, 266], [30, 108, 146, 200, 219]]
    g.add_vertex(-1)
    g.seidel_switching(sum(C,[]))
    g.relabel()
    g.name('')
    return g

def SRG_280_135_70_60():
    r"""
    Return a strongly regular graph with parameters `(280, 135, 70, 60)`.

    This graph is built from the action of `J_2` on a `3.PGL(2,9)` subgroup it
    contains.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_280_135_70_60
        sage: g=SRG_280_135_70_60()                  # long time # optional - gap_packages
        sage: g.is_strongly_regular(parameters=True) # long time # optional - gap_packages
        (280, 135, 70, 60)
    """
    from sage.interfaces.gap import gap
    from sage.groups.perm_gps.permgroup import PermutationGroup
    from sage.graphs.graph import Graph

    gap.load_package("AtlasRep")

    # A representation of J2 acting on a 3.PGL(2,9) it contains.
    J2    = PermutationGroup(gap('AtlasGenerators("J2",2).generators'))
    edges = J2.orbit((1,2),"OnSets")
    g     = Graph()
    g.add_edges(edges)
    g.relabel()
    return g

def SRG_280_117_44_52():
    r"""
    Return a strongly regular graph with parameters `(280, 117, 44, 52)`.

    This graph is built according to a very pretty construction of Mathon and
    Rosa [MR85]_:

        The vertices of the graph `G` are all partitions of a set of 9 elements
        into `\{\{a,b,c\},\{d,e,f\},\{g,h,i\}\}`. The cross-intersection of two
        such partitions `P=\{P_1,P_2,P_3\}` and `P'=\{P'_1,P'_2,P'_3\}` being
        defined as `\{P_i \cap P'_j: 1\leq i,j\leq 3\}`, two vertices of `G` are
        set to be adjacent if the cross-intersection of their respective
        partitions does not contain exactly 7 nonempty sets.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_280_117_44_52
        sage: g=SRG_280_117_44_52()
        sage: g.is_strongly_regular(parameters=True)
        (280, 117, 44, 52)

    REFERENCE:

    .. [MR85] R. Mathon and A. Rosa,
       A new strongly regular graph,
       Journal of Combinatorial Theory, Series A 38, no. 1 (1985): 84-86.
       http://dx.doi.org/10.1016/0097-3165(85)90025-1
    """
    from sage.graphs.hypergraph_generators import hypergraphs

    # V is the set of partions {{a,b,c},{d,e,f},{g,h,i}} of {0,...,8}
    H = hypergraphs.CompleteUniform(9,3)
    g = H.intersection_graph()
    V = g.complement().cliques_maximal()
    V = map(frozenset,V)

    # G is the graph defined on V in which two vertices are adjacent when they
    # corresponding partitions cross-intersect on 7 nonempty sets
    G = Graph([V, lambda x,y:
               sum(any(xxx in yy for xxx in xx) for xx in x for yy in y) != 7],
              loops=False)
    return G

def strongly_regular_from_two_weight_code(L):
    r"""
    Return a strongly regular graph from a two-weight code.

    A code is said to be a *two-weight* code the weight of its nonzero codewords
    (i.e. their number of nonzero coordinates) can only be one of two integer
    values `w_1,w_2`. It is said to be *projective* if the minimum weight of the
    dual code is `\geq 3`. A strongly regular graph can be built from a
    two-weight projective code with weights `w_1,w_2` (assuming `w_1<w_2`) by
    adding an edge between any two codewords whose difference has weight
    `w_1`. For more information, see [vLintSchrijver81]_ or [Delsarte72]_.

    INPUT:

    - ``L`` -- a two-weight linear code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import strongly_regular_from_two_weight_code
        sage: x=("100022021001111",
        ....:    "010011211122000",
        ....:    "001021112100011",
        ....:    "000110120222220")
        sage: M = Matrix(GF(3),[list(l) for l in x])
        sage: G = strongly_regular_from_two_weight_code(LinearCode(M))
        sage: G.is_strongly_regular(parameters=True)
        (81, 50, 31, 30)

    REFERENCES:

    .. [vLintSchrijver81] J. H. van Lint, and A. Schrijver (1981),
      Construction of strongly regular graphs, two-weight codes and
      partial geometries by finite fields,
      Combinatorica, 1(1), 63-73.

    .. [Delsarte72] Ph. Delsarte,
      Weights of linear codes and strongly regular normed spaces,
      Discrete Mathematics (1972), Volume 3, Issue 1, Pages 47-64,
      http://dx.doi.org/10.1016/0012-365X(72)90024-6.

    """
    V = map(tuple,list(L))
    w1, w2 = sorted(set(sum(map(bool,x)) for x in V).difference([0]))
    G = Graph([V,lambda u,v: sum(uu!=vv for uu,vv in zip(u,v)) == w1])
    G.relabel()
    return G

def SRG_256_187_138_132():
    r"""
    Return a `(256, 187, 138, 132)`-strongly regular graph.

    This graph is built from a projective binary `[68,8]` code with weights `32,
    40`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_256_187_138_132
        sage: G = SRG_256_187_138_132()
        sage: G.is_strongly_regular(parameters=True)
        (256, 187, 138, 132)
    """
    x=("10000000100111100110000001101000100111000011100101011010111111010110",
       "01000000010011110011000000110100010011100001110010101101011111101011",
       "00100000001001111101100000011010001001110000111001010110101111110101",
       "00010000100011011100110001100101100011111011111001100001101000101100",
       "00001000110110001100011001011010011110111110011001111010001011000000",
       "00000100111100100000001101000101101000011100101001110111111010110110",
       "00000010011110010000000110100010111100001110010100101011111101011011",
       "00000001001111001100000011010001011110000111001010010101111110101101")
    M = Matrix(GF(2),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_416_100_36_20():
    r"""
    Return a `(416,100,36,20)`-strongly regular graph.

    This graph is obtained as an orbit on sets of cardinality 2
    (among 2 that exists) of the group `G_2(4)`.
    This graph is isomorphic to the subgraph of the from :meth:`Suzuki Graph
    <sage.graphs.graph_generators.GraphGenerators.SuzukiGraph>` induced on
    the neighbors of a vertex.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_416_100_36_20
        sage: g = SRG_416_100_36_20()                # optional - gap_packages # long time
        sage: g.is_strongly_regular(parameters=True) # optional - gap_packages # long time
        (416, 100, 36, 20)
    """
    from sage.libs.gap.libgap import libgap
    libgap.LoadPackage("AtlasRep")
    g=libgap.AtlasGroup("G2(4)",libgap.NrMovedPoints,416)
    h = Graph()
    h.add_edges(g.Orbit([1,5],libgap.OnSets))
    h.relabel()
    return h

def SRG_560_208_72_80():
    r"""
    Return a `(560,208,72,80)`-strongly regular graph

    This graph is obtained as the union of 4 orbits of sets of cardinality 2
    (among the 13 that exists) of the group `Sz(8)`.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_560_208_72_80
        sage: g = SRG_560_208_72_80()                # optional - database_gap # not tested (~2s)
        sage: g.is_strongly_regular(parameters=True) # optional - database_gap # not tested (~2s)
        (560, 208, 72, 80)
    """
    from sage.libs.gap.libgap import libgap
    libgap.LoadPackage("AtlasRep")
    g=libgap.AtlasGroup("Sz8",libgap.NrMovedPoints,560)

    h = Graph()
    h.add_edges(g.Orbit([1,2],libgap.OnSets))
    h.add_edges(g.Orbit([1,4],libgap.OnSets))
    h.add_edges(g.Orbit([1,8],libgap.OnSets))
    h.add_edges(g.Orbit([1,27],libgap.OnSets))
    h.relabel()
    return h

def strongly_regular_from_two_intersection_set(M):
    r"""
    Return a strongly regular graph from a 2-intersection set.

    A set of points in the projective geometry `PG(k,q)` is said to be a
    2-intersection set if it intersects every hyperplane in either `h_1` or
    `h_2` points, where `h_1,h_2\in \\NN`.

    From a 2-intersection set `S` can be defined a strongly-regular graph in the
    following way:

    - Place the points of `S` on a hyperplane `H` in `PG(k+1,q)`

    - Define the graph `G` on all points of `PG(k+1,q)\backslash H`

    - Make two points of `V(G)=PG(k+1,q)\backslash H` adjacent if the line going
      through them intersects `S`

    For more information, see e.g. [CDB13]_ where this explanation has been
    taken from.

    INPUT:

    - `M` -- a `|S| \times k` matrix with entries in `F_q` representing the points of
      the 2-intersection set. We assume that the first non-zero entry of each row is
      equal to `1`, that is, they give points in homogeneous coordinates.

    The implementation does not check that `S` is actually a 2-intersection set.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import strongly_regular_from_two_intersection_set
        sage: S=Matrix([(0,0,1),(0,1,0)] + map(lambda x: (1,x^2,x), GF(4,'b')))
        sage: g=strongly_regular_from_two_intersection_set(S)
        sage: g.is_strongly_regular(parameters=True)
        (64, 18, 2, 6)

    REFERENCES:

    .. [CDB13] I. Cardinali and B. De Bruyn,
      Spin-embeddings, two-intersection sets and two-weight codes,
      Ars Comb. 109 (2013): 309-319.
      https://biblio.ugent.be/publication/4241842/file/4241845.pdf
    """
    from itertools import product, izip
    K = M.base_ring()
    k = M.ncols()
    g = Graph()

    M = [list(p) for p in M]

    # For every point in F_q^{k+1} not on the hyperplane of M
    for u in [tuple(x) for x in product(K,repeat=k)]:
        # For every v point of M
        for v in M:
            # u is adjacent with all vertices on a uv line.
            g.add_edges([[u,tuple([u[i]+qq*v[i] for i in range(k)])] \
                                            for qq in K if not qq==K.zero()])
    g.relabel()
    return g


def SRG_729_336_153_156():
    r"""
    Return a `(729, 336, 153, 156)`-strongly regular graph.

    This graph is built from a 2-intersection code shared by L. Disset in his
    thesis [Disset00]_ and available at
    http://www.mat.uc.cl/~ldissett/newgraphs/.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_336_153_156
        sage: G = SRG_729_336_153_156()               # long time
        sage: G.is_strongly_regular(parameters=True)  # long time
        (729, 336, 153, 156)

    REFERENCES:

    .. [Disset00] L. Dissett,
       Combinatorial and computational aspects of finite geometries,
       2000,
       https://tspace.library.utoronto.ca/bitstream/1807/14575/1/NQ49844.pdf
    """
    L = [
        "101212212122202012010102120101112012121001201012120220122112001121201201201201010020012201001201201201202120121122012021201221021110200212121011211002012220000122201201",
        "011100122001200111220011220020011222001200022000220012220122011220011101122012012001222010122200012011120112220112000120120012002012201122001220012122000201212001211211",
        "000011111000011111112000001112000000111122222000001111112222000001111122222000111222222001111122222000001111112222000001112222000111122222000001111222000011122000011122",
        "000000000111111111111000000000111111111111111222222222222222000000000000000111111111111222222222222000000000000000111111111111222222222222000000000000111111111222222222",
        "000000000000000000000111111111111111111111111111111111111111000000000000000000000000000000000000000111111111111111111111111111111111111111222222222222222222222222222222",
        "000000000000000000000000000000000000000000000000000000000000111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111",
    ]

    L = Matrix(GF(3),map(list,L)).transpose()
    return strongly_regular_from_two_intersection_set(L)

def SRG_729_448_277_272():
    r"""
    Return a `(729, 448, 277, 272)`-strongly regular graph.

    This graph is built from a ternary `[140, 6]` code with weights `90, 99`,
    found by Axel Kohnert [Kohnert07]_ and shared by Alfred Wassermann.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_448_277_272
        sage: G = SRG_729_448_277_272()              # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (729, 448, 277, 272)
    """
    x = ("10111011111111101110101110111100111011111011101111101001001111011011011111100100111101000111101111101100011011001111101110111110101111111001",
         "01220121111211011101011101112101220022120121011222010110011010120110112112001101021010101111012211011000020110012221212101011101211122020011",
         "22102021112110111120211021122012100012202220112110101200110101202102122120011110020201211110021210110000101200121222122010211022211210110101",
         "11010221121101111102210221220221000111011101121102012101101012012022222000211200202012211100111201200001122001211011120102110212212102121001",
         "20201121211111111012202022201210001220122121211010121011010020110121220201212002010222011001111012100011010212110021202021102112221012110011",
         "02022222111111110112020112011200022102212222110102210110100101102211201211220020002120110011110221100110002121100222120211021112010112220101")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_729_532_391_380():
    r"""
    Return a `(729, 532, 391, 380)`-strongly regular graph.

    This graph is built from a projective ternary `[98,6]` code with weights
    `63, 72`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_532_391_380
        sage: G = SRG_729_532_391_380()               # long time
        sage: G.is_strongly_regular(parameters=True)  # long time
        (729, 532, 391, 380)
    """
    x=("10000021022112121121110122000110112002010011100120022110120200120111220220122120012012100201110210",
       "01000020121020200200211101202121120002211002210100021021202220112122012212101102010210010221221201",
       "00100021001211011111111202120022221002201111021101021212210122101020121111002000210000101222202000",
       "00010022122200222202201212211112001102200112202202121201211212010210202001222120000002110021000110",
       "00001021201002010011020210221221012112200012020011201200111021021102212120211102012002011201210221",
       "00000120112212122122202110022202210010200022002120112200101002202221111102110100210212001022201202")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_729_560_433_420():
    r"""
    Return a `(729, 560, 433, 420)`-strongly regular graph.

    This graph is built from a projective ternary `[84,6]` code with weights
    `54, 63`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_560_433_420
        sage: G = SRG_729_560_433_420()               # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (729, 560, 433, 420)
    """
    x=("100000210221121211211212100002020022102220010202100220112211111022012202220001210020",
       "010000201210202002002200010022222022012112111222010212120102222221210102112001001022",
       "001000210012110111111202101021212221000101021021021211021221000111100202101200010122",
       "000100221222002222022202010121111210202200012001222011212000211200122202100120211002",
       "000010212010020100110002001011101112122110211102212121200111102212021122100010201120",
       "000001201122121221222212000110100102011101201012001102201222221110211011100001200102")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_729_616_523_506():
    r"""
    Return a `(729, 616, 523, 506)`-strongly regular graph.

    This graph is built from a projective ternary `[56,6]` code with weights
    `36, 45`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_616_523_506
        sage: G = SRG_729_616_523_506()              # not tested (3s)
        sage: G.is_strongly_regular(parameters=True) # not tested (3s)
        (729, 616, 523, 506)
    """
    x=("10000021022112022210202200202122221120200112100200111102",
       "01000020121020221101202120220001110202220110010222122212",
       "00100021001211211020022112222122002210122100101222020020",
       "00010022122200010012221111121001121211212002110020010101",
       "00001021201002220211121011010222000111021002011201112112",
       "00000120112212111201011001002111121101002212001022222010")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_625_364_213_210():
    r"""
    Return a `(625, 364, 213, 210)`-strongly regular graph.

    This graph is built from a projective 5-ary `[88,5]` code with weights `64,
    72`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_625_364_213_210
        sage: G = SRG_625_364_213_210()              # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (625, 364, 213, 210)
    """
    x=("10004323434444234221223441130101034431234004441141003110400203240",
       "01003023101220331314013121123212111200011403221341101031340421204",
       "00104120244011212302124203142422240001230144213220111213034240310",
       "00012321211123213343321143204040211243210011144140014401003023101")
    M = Matrix(GF(5),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_625_416_279_272():
    r"""
    Return a `(625, 416, 279, 272)`-strongly regular graph.

    This graph is built from a projective 5-ary `[52,4]` code with weights `40,
    45`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_625_416_279_272
        sage: G = SRG_625_416_279_272()               # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (625, 416, 279, 272)
    """
    x=("1000432343444423422122344123113041011022221414310431",
       "0100302310122033131401312133032331123141114414001300",
       "0010412024401121230212420301411224123332332300210011",
       "0001232121112321334332114324420140440343341412401244")
    M = Matrix(GF(5),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_625_468_353_342():
    r"""
    Return a `(625, 468, 353, 342)`-strongly regular graph.

    This graph is built from a two-weight code presented in [BJ03]_ (cf. Theorem
    4.1).

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_625_468_353_342
        sage: G = SRG_625_468_353_342()              # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (625, 468, 353, 342)

    REFERENCE:

    .. [BJ03] I. Bouyukliev and S. Juriaan,
      Some new results on optimal codes over `F_5`,
      Designs, Codes and Cryptography 30, no. 1 (2003): 97-111,
      http://www.moi.math.bas.bg/moiuser/~iliya/pdf_site/gf5srev.pdf
    """
    x = ("111111111111111111111111111111000000000",
         "111111222222333333444444000000111111000",
         "223300133440112240112240133440123400110",
         "402340414201142301132013234230044330401")
    M = Matrix(GF(5),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_243_220_199_200():
    r"""
    Return a `(243, 220, 199, 200)`-strongly regular graph.

    This graph is built from a projective ternary `[55,5]` code with weights
    `36, 45`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_243_220_199_200
        sage: G = SRG_243_220_199_200()
        sage: G.is_strongly_regular(parameters=True)
        (243, 220, 199, 200)
    """
    x=("1000010122200120121002211022111101011212112022022020002",
       "0100011101120102100102202121022211112000020211221222002",
       "0010021021222220122011212220021121100021220002100102201",
       "0001012221012012100200102211110211121211201002202000222",
       "0000101222101201210020110221111020112121120120220200022")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_729_476_313_306():
    r"""
    Return a `(729, 476, 313, 306)`-strongly regular graph.

    This graph is built from a projective ternary `[126,6]` code with weights
    `81, 90`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_476_313_306
        sage: G = SRG_729_476_313_306()               # not tested (5s)
        sage: G.is_strongly_regular(parameters=True) # not tested (5s)
        (729, 476, 313, 306)
    """
    x=("100000210221121211211101220021210000100011020200201101121021122102020111100122122221120200110001010222000021110110011211110210",
       "010000201210202002002111012020001001110012222220221211200120201212222102210100001110202220121001110211200120221121012001221201",
       "001000210012110111111112021220210102211012212122200222212000112220212011021102122002210122122101120210120100102212112112202000",
       "000100221222002222022012122120201012021112211112111120010221100121011012202201001121211212002211120210012201120021222121000110",
       "000010212010020100110202102200200102002122111011112210121010202111121212020010222000111021000222122210001011222102100121210221",
       "000001201122121221222021100221200012000220101001022022100122112010102222002122111121101002200020221110000122202000221222201202")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_729_420_243_240():
    r"""
    Return a `(729, 420, 243, 240)`-strongly regular graph.

    This graph is built from a projective ternary `[154,6]` code with weights
    `99, 108`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_729_420_243_240
        sage: G = SRG_729_420_243_240()               # not tested (5s)
        sage: G.is_strongly_regular(parameters=True) # not tested (5s)
        (729, 420, 243, 240)
    """
    x=("10000021022112121121110122002121000010001102020020110112102112202221021020201"+
       "20202212102220222022222110122210022201211222111110211101121002011102101111002",
       "01000020121020200200211101202000100111001222222022121120012020122110122122221"+
       "02222102012112111221111021101101021121002001022221202211100102212212010222102",
       "00100021001211011111111202122021010221101221212220022221200011221102002202120"+
       "20121121000101000111020212200020121210011112210001001022001012222020000100212",
       "00010022122200222202201212212020101202111221111211112001022110001001221210110"+
       "12211020202200222000021101010212001022212020002112011200021100210001100121020",
       "00001021201002010011020210220020010200212211101111221012101020222021111111212"+
       "11120012122110211222201220220201222200102101111020112221020112012102211120101",
       "00000120112212122122202110022120001200022010100102202210012211211120100101022"+
       "01011212011101110111112202111200111021221112222211222020120010222012022220012")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_1024_825_668_650():
    r"""
    Return a `(1024, 825, 668, 650)`-strongly regular graph.

    This graph is built from a projective binary `[198,10]` code with weights
    `96, 112`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_1024_825_668_650
        sage: G = SRG_1024_825_668_650()               # not tested (13s)
        sage: G.is_strongly_regular(parameters=True)   # not tested (13s)
        (1024, 825, 668, 650)
    """
    x=("1000000000111111101010000100011001111101101010010010011110001101111001101100111000111101010101110011"+
       "11110010100111101001001100111101011110111100101101110100111100011111011011100111110010100110110000",
       "0100000000010110011100100010101010101111011010001001010110011010101011011101000110000001101101010110"+
       "10110111110101000000011011001100010111110001001011011100111100100000110001011001110110011101011000",
       "0010000000011100111110111011000011010100100011110000001100011011101111001010001100110110000001111000"+
       "11000000101011010111110101000111110010011011101110000010110100000011100010011111100100111101010010",
       "0001000000001111100010000000100101010001110111100010010010010111000100101100010001001110111101110100"+
       "10010101101100110011010011101100110100100011011101100000110011110011111000000010110101011111101111",
       "0000100000110010010000010110000111010011010101000010110100101010011011000011001100001110011011110001"+
       "11101000010000111101101100111100001011010010111011100101101001111000100011000010110111111111011100",
       "0000010000110100111001111011010000101110001011100010010010010111100101011001011011100110101110100001"+
       "01101010110010100011000101111100100001110111001001001001001100001101110110000110101010011010101101",
       "0000001000011011110010110100010010001100000011001000011101000110001101001000110110010101011011001111"+
       "01111111010011111010100110011001110001001000001110000110111011010000011101001110111001011011001011",
       "0000000100111001101011110010111100100001010100100110001100100110010101111001100101101001000101011000"+
       "10001001111101011101001001010111010011011101010011010000101010011001010110011110010000011011111001",
       "0000000010101011010101010101011100111101111110100011011001001010111101100111010110100101100110101100"+
       "00000001100011110110010101100001000000010100001101111011111000110001100101101010000001110101011100",
       "0000000001101100111101011000010000000011010100000110101010011010100111100001000011010011011101110111"+
       "01110111011110101100100100110110011100001001000001010011010010010111110011101011101001101101011010")
    M = Matrix(GF(2),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_512_73_12_10():
    r"""
    Return a `(512, 73, 12, 10)`-strongly regular graph.

    This graph is built from a projective binary `[219,9]` code with weights
    `96, 112`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_512_73_12_10
        sage: G = SRG_512_73_12_10()                 # not tested (3s)
        sage: G.is_strongly_regular(parameters=True) # not tested (3s)
        (512, 73, 12, 10)
    """
    x=("10100011001110100010100010010000100100001011110010001010011000000001101011110011001001000010011110111011111"+
       "0001001010110110110111001100111100011011101000000110101110001010100011110011111111110111010100101011000101111111",
       "01100010110101110100001000010110001010010010011000111101111001011101000011101011100111111110001100000111010"+
       "1101001000110001111011001100101011110101011110010001101011110000100000101101100010110100001111001100110011001111",
       "00010010001001011011001110011101111110000000101110101000110110011001110101011011101011011011000010010011111"+
       "1110110100111111000000110011101101000000001010000000011000111111100101100001110011110001110011110110100111100001",
       "00001000100010101110101110011100010101110011010110000001111111100111010000101110001010100100000001011010111"+
       "1001001000000011000011001100100100111010000000001010111001001100100101011110001100110001000000111001100100100111",
       "00000101010100010101101110011101001000101110000000000111101100011000000001110100000001011010101001111110110"+
       "0010110111100111000000110011110110101101110000001111100001010001100101100001110011110001101101000000000000100001",
       "00000000000000000000010000011101011100100010000110110100101011001011001100000001011000101010100111000111101"+
       "0011100011011011011111100010011100010111101001011001001101100010011010001011010110001110100001001111110010100100",
       "00000000000000000000000001011010110110101111010110101001001001000101010000000000001011000011000010100100110"+
       "0000110000111101100010000111111111101101001010110000111111101110101011010010010001011101110011111001100100101110",
       "00000000000000000000000000110111101011110010101110000110010010100010001010000000010100011000101000010011000"+
       "0110000111100110100001001011111111111010110000001010111111110011110110001100100010101011101101110110011000110110",
       "00000000000000000000000000000000000000000000000001111111111111111111111110000001111111111111111111111111111"+
       "1111111100000000000011111111111111000000111111111111111111000000000000111111111111000000000000000000111111000110")
    M = Matrix(GF(2),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_512_219_106_84():
    r"""
    Return a `(512, 219, 106, 84)`-strongly regular graph.

    This graph is built from a projective binary `[73,9]` code with weights `32,
    40`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_512_219_106_84
        sage: G = SRG_512_219_106_84()
        sage: G.is_strongly_regular(parameters=True)
        (512, 219, 106, 84)
    """
    x=("1010010100000010100000101010001100110101101101000010110010100100111011101",
       "0110000110000101101111001101000100111111101011011101110010110001100111100",
       "0001010000000001111111011010100101001111011010101100001010000001110100001",
       "0000100100000001111111100111000011110011110101000001010110000001011010001",
       "0000001010000001111110111100011000111100101110010010101100000001101001001",
       "0000000001000111001010110010011001101001011010110110011001010111100010010",
       "0000000000100100011000100100111100001100101111010001011011111000110011110",
       "0000000000010111001100101011111110101010000000000100111110000001111111100",
       "0000000000001011100001000011011010110001110101101100001100101110101110110")
    M = Matrix(GF(2),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_512_315_202_180():
    r"""
    Return a `(512, 315, 202, 180)`-strongly regular graph.

    This graph is built from a projective binary code with weights `32, 40`,
    found by Axel Kohnert [Kohnert07]_ and shared by Alfred Wassermann.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly
        regular graph from a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_512_315_202_180
        sage: G = SRG_512_315_202_180()              # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (512, 315, 202, 180)

    REFERENCE:

    .. [Kohnert07] A. Kohnert,
       Constructing two-weight codes with prescribed groups of automorphisms,
       Discrete applied mathematics 155, no. 11 (2007): 1451-1457.
       http://linearcodes.uni-bayreuth.de/twoweight/
    """
    x=("0100011110111000001011010110110111100010001000001000001001010110101101",
       "1000111101110000000110101111101111000100010000010000000010101111001011",
       "0001111011100000011101011101011110011000100000100000000101011100010111",
       "0011110101000000111010111010111100110001000011000000001010111000101101",
       "0111101000000001110101110111111001100010000100000000010101110011001011",
       "1111010000000011101011101101110011010100001000000000101011100100010111",
       "1110100010000111000111011011100110111000010000000001000111001010101101",
       "1101000110001110001110110101001101110000100010000010001110010101001011",
       "1010001110011100001101101010011011110001000100000100001100101010010111")
    M = Matrix(GF(2),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_256_153_92_90():
    r"""
    Return a `(256, 153, 92, 90)`-strongly regular graph.

    This graph is built from a projective 4-ary `[34,4]` code with weights `24,
    28`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_256_153_92_90
        sage: G = SRG_256_153_92_90()
        sage: G.is_strongly_regular(parameters=True)
        (256, 153, 92, 90)
    """
    K = GF(4,conway=True, prefix='x')
    F = K.gens()[0]
    J = F*F
    x = [[1,0,0,0,1,F,F,J,1,0,F,F,0,1,J,F,F,J,J,J,F,F,J,J,J,1,J,F,1,0,1,F,J,1],
         [0,1,0,0,F,F,1,J,1,1,J,1,F,F,0,0,1,0,F,F,0,1,J,F,F,1,0,0,0,1,F,F,J,1],
         [0,0,1,0,1,0,0,F,F,1,J,1,1,J,1,F,F,F,J,1,0,F,F,0,1,J,F,F,1,0,0,0,1,F],
         [0,0,0,1,F,F,J,1,0,F,F,0,1,J,F,F,1,J,J,F,F,J,J,J,1,J,F,1,0,1,F,J,1,J]]
    M = Matrix(K,[map(K,l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_256_170_114_110():
    r"""
    Return a `(256, 170, 114, 110)`-strongly regular graph.

    This graph is built from a projective binary `[85,8]` code with weights `40,
    48`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_256_170_114_110
        sage: G = SRG_256_170_114_110()
        sage: G.is_strongly_regular(parameters=True)
        (256, 170, 114, 110)
    """
    x=("1000000010011101010001000011100111000111111010110001101101000110010011001101011100001",
       "0100000011010011111001100010010100100100000111101001011011100101011010101011110010001",
       "0010000011110100101101110010101101010101111001000101000000110100111110011000100101001",
       "0001000011100111000111111010110001101101000110010011001101011100001100000001001110101",
       "0000100011101110110010111110111111110001011001111000001011101000010101001101111011011",
       "0000010011101010001000011100111000111111010110001101101000110010011001101011100001100",
       "0000001001110101000100001110011100011111101011000110110100011001001100110101110000110",
       "0000000100111010100010000111001110001111110101100011011010001100100110011010111000011")
    M = Matrix(GF(2),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_120_63_30_36():
    r"""
    Return a `(120,63,30,36)`-strongly regular graph

    It is the distance-2 graph of :meth:`JohnsonGraph(10,3)
    <sage.graphs.graph_generators.GraphGenerators.JohnsonGraph>`.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import SRG_120_63_30_36
        sage: G =  SRG_120_63_30_36()
        sage: G.is_strongly_regular(parameters=True)
        (120, 63, 30, 36)
    """
    from sage.graphs.generators.families import JohnsonGraph
    return JohnsonGraph(10,3).distance_graph([2])

def SRG_126_25_8_4():
    r"""
    Return a `(126,25,8,4)`-strongly regular graph

    It is the distance-(1 or 4) graph of :meth:`JohnsonGraph(9,4)
    <sage.graphs.graph_generators.GraphGenerators.JohnsonGraph>`.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import SRG_126_25_8_4
        sage: G =  SRG_126_25_8_4()
        sage: G.is_strongly_regular(parameters=True)
        (126, 25, 8, 4)
    """
    from sage.graphs.generators.families import JohnsonGraph
    return JohnsonGraph(9,4).distance_graph([1,4])

def SRG_175_72_20_36():
    r"""
    Return a `(175,72,20,36)`-strongly regular graph

    This graph is obtained from the line graph of
    :meth:`~sage.graphs.graph_generators.GraphGenerators.HoffmanSingletonGraph`. Setting
    two vertices to be adjacent if their distance in the line graph is exactly
    two yields the strongly regular graph. For more information, see
    http://www.win.tue.nl/~aeb/graphs/McL.html.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import SRG_175_72_20_36
        sage: G = SRG_175_72_20_36()
        sage: G.is_strongly_regular(parameters=True)
        (175, 72, 20, 36)
    """
    return HoffmanSingletonGraph().line_graph().distance_graph([2])

def SRG_126_50_13_24():
    r"""
    Return a `(126,50,13,24)`-strongly regular graph

    This graph is a subgraph of
    :meth:`~sage.graphs.strongly_regular_db.SRG_175_72_20_36`.
    This construction, due to Goethals, is given in §10B.(vii) of [BvL84]_.

    EXAMPLES::

        sage: from sage.graphs.strongly_regular_db import SRG_126_50_13_24
        sage: G = SRG_126_50_13_24()
        sage: G.is_strongly_regular(parameters=True)
        (126, 50, 13, 24)
    """
    from sage.graphs.generators.smallgraphs import HoffmanSingletonGraph
    from sage.graphs.strongly_regular_db import SRG_175_72_20_36
    hs = HoffmanSingletonGraph()
    s = set(hs.vertices()).difference(hs.neighbors(0)+[0])
    return SRG_175_72_20_36().subgraph(hs.edge_boundary(s,s))

def SRG_81_50_31_30():
    r"""
    Return a `(81, 50, 31, 30)`-strongly regular graph.

    This graph is built from a projective ternary `[15,4]` code with weights `9,
    12`, obtained from Eric Chen's `database of two-weight codes
    <http://moodle.tec.hkr.se/~chen/research/2-weight-codes/search.php>`__.

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_81_50_31_30
        sage: G = SRG_81_50_31_30()
        sage: G.is_strongly_regular(parameters=True)
        (81, 50, 31, 30)
    """
    x=("100022021001111",
       "010011211122000",
       "001021112100011",
       "000110120222220")
    M = Matrix(GF(3),[list(l) for l in x])
    return strongly_regular_from_two_weight_code(LinearCode(M))

def SRG_1288_792_476_504():
    r"""
    Return a `(1288, 792, 476, 504)`-strongly regular graph.

    This graph is built on the words of weight 12 in the
    :func:`~sage.coding.code_constructions.BinaryGolayCode`. Two of them are
    then made adjacent if their symmetric difference has weight 12 (cf
    [BvE92]_).

    .. SEEALSO::

        :func:`strongly_regular_from_two_weight_code` -- build a strongly regular graph from
        a two-weight code.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import SRG_1288_792_476_504
        sage: G = SRG_1288_792_476_504()             # long time
        sage: G.is_strongly_regular(parameters=True) # long time
        (1288, 792, 476, 504)

    REFERENCE:

    .. [BvE92] A. Brouwer and C. Van Eijl,
      On the p-Rank of the Adjacency Matrices of Strongly Regular Graphs
      Journal of Algebraic Combinatorics (1992), vol.1, n.4, pp329-346,
      http://dx.doi.org/10.1023/A%3A1022438616684
    """
    from sage.coding.code_constructions import BinaryGolayCode
    C = BinaryGolayCode()
    C = [[i for i,v in enumerate(c) if v]
         for c in C]
    C = [s for s in C if len(s) == 12]
    G = Graph([map(frozenset,C),
               lambda x,y:len(x.symmetric_difference(y))==12])
    G.relabel()
    return G


cdef bint seems_feasible(int v, int k, int l, int mu):
    r"""
    Tests is the set of parameters seems feasible

    INPUT:

    - ``v,k,l,mu`` (integers)
    """
    cdef int r,s,f,g
    cdef uint_fast32_t tmp[2]

    if (v<0 or k<=0 or l<0 or mu<0 or
        k>=v-1 or l>=k or mu>=k or
        v-2*k+mu-2 < 0 or # lambda of complement graph >=0
        v-2*k+l    < 0 or # μ of complement graph >=0
        mu*(v-k-1) != k*(k-l-1)):
        return False

    # Conference graphs. Only possible if 'v' is a sum of two squares (3.A of
    # [BvL84]
    if (v-1)*(mu-l)-2*k == 0:
        return two_squares_c(v,tmp)

    rr,ss = eigenvalues(v,k,l,mu)
    if rr is None:
        return False
    r,s = rr,ss

    # 1.3.1 of [Distance-regular graphs]
    # "Integrality condition"
    if ((s+1)*(k-s)*k) % (mu*(s-r)):
        return False

    # Theorem 21.3 of [WilsonACourse] or
    # 3.B of [BvL84]
    # (Krein conditions)
    if ((r+1)*(k+r+2*r*s) > (k+r)*(s+1)**2 or
        (s+1)*(k+s+2*r*s) > (k+s)*(r+1)**2):
        return False

    # multiplicity of eigenvalues 'r,s' (f=lambda_r, g=lambda_s)
    #
    # They are integers (checked by the 'integrality condition').
    f = -k*(s+1)*(k-s)/((k+r*s)*(r-s))
    g =  k*(r+1)*(k-r)/((k+r*s)*(r-s))

    # 3.C of [BvL84]
    # (Absolute bound)
    if (2*v > f*(f+3) or
        2*v > g*(g+3)):
        return False

    # 3.D of [BvL84]
    # (Claw bound)
    if (mu != s**2    and
        mu != s*(s+1) and
        2*(r+1) > s*(s+1)*(mu+1)):
        return False

    # 3.E of [BvL84]
    # (the Case μ=1)
    if mu == 1:
        if (   k  % (l+1) or
            (v*k) % ((l+1)*(l+2))):
            return False

    # 3.F of [BvL84]
    # (the Case μ=2)
    if mu == 2 and 2*k < l*(l+3) and k%(l+1):
        return False

    return True

def strongly_regular_graph(int v,int k,int l,int mu=-1,bint existence=False,bint check=True):
    r"""
    Return a `(v,k,\lambda,\mu)`-strongly regular graph.

    This function relies partly on Andries Brouwer's `database of strongly
    regular graphs <http://www.win.tue.nl/~aeb/graphs/srg/srgtab.html>`__. See
    the documentation of :mod:`sage.graphs.strongly_regular_db` for more
    information.

    INPUT:

    - ``v,k,l,mu`` (integers) -- note that ``mu``, if unspecified, is
      automatically determined from ``v,k,l``.

    - ``existence`` (boolean;``False``) -- instead of building the graph,
      return:

        - ``True`` -- meaning that a `(v,k,\lambda,\mu)`-strongly regular graph
          exists.

        - ``Unknown`` -- meaning that Sage does not know if such a strongly
          regular graph exists (see :mod:`sage.misc.unknown`).

        - ``False`` -- meaning that no such strongly regular graph exists.

    - ``check`` -- (boolean) Whether to check that output is correct before
      returning it. As this is expected to be useless (but we are cautious
      guys), you may want to disable it whenever you want speed. Set to
      ``True`` by default.

    EXAMPLES:

    Petersen's graph from its set of parameters::

        sage: graphs.strongly_regular_graph(10,3,0,1,existence=True)
        True
        sage: graphs.strongly_regular_graph(10,3,0,1)
        complement(Johnson graph with parameters 5,2): Graph on 10 vertices

    Now without specifying `\mu`::

        sage: graphs.strongly_regular_graph(10,3,0)
        complement(Johnson graph with parameters 5,2): Graph on 10 vertices

    An obviously infeasible set of parameters::

        sage: graphs.strongly_regular_graph(5,5,5,5,existence=True)
        False
        sage: graphs.strongly_regular_graph(5,5,5,5)
        Traceback (most recent call last):
        ...
        ValueError: There exists no (5, 5, 5, 5)-strongly regular graph

    An set of parameters proved in a paper to be infeasible::

        sage: graphs.strongly_regular_graph(324,57,0,12,existence=True)
        False
        sage: graphs.strongly_regular_graph(324,57,0,12)
        Traceback (most recent call last):
        ...
        EmptySetError: Andries Brouwer's database reports that no (324, 57, 0,
        12)-strongly regular graph exists. Comments: <a
        href="srgtabrefs.html#GavrilyukMakhnev05">Gavrilyuk & Makhnev</a> and <a
        href="srgtabrefs.html#KaskiOstergard07">Kaski & stergrd</a>

    A set of parameters unknown to be realizable in Andries Brouwer's database::

        sage: graphs.strongly_regular_graph(324,95,22,30,existence=True)
        Unknown
        sage: graphs.strongly_regular_graph(324,95,22,30)
        Traceback (most recent call last):
        ...
        RuntimeError: Andries Brouwer's database reports that no
        (324,95,22,30)-strongly regular graph is known to exist.
        Comments:

    A large unknown set of parameters (not in Andries Brouwer's database)::

        sage: graphs.strongly_regular_graph(1394,175,0,25,existence=True)
        Unknown
        sage: graphs.strongly_regular_graph(1394,175,0,25)
        Traceback (most recent call last):
        ...
        RuntimeError: Sage cannot figure out if a (1394,175,0,25)-strongly regular graph exists.

    Test the Claw bound (see 3.D of [BvL84]_)::

        sage: graphs.strongly_regular_graph(2058,242,91,20,existence=True)
        False
    """
    load_brouwer_database()
    if mu == -1:
        mu = k*(k-l-1)//(v-k-1)

    params = (v,k,l,mu)
    params_complement = (v,v-k-1,v-2*k+mu-2,v-2*k+l)

    if not seems_feasible(v,k,l,mu):
        if existence:
            return False
        raise ValueError("There exists no "+str(params)+"-strongly regular graph")

    def check_srg(G):
        if check and (v,k,l,mu) != G.is_strongly_regular(parameters=True):
            raise RuntimeError("Sage built an incorrect {}-SRG.".format((v,k,l,mu)))
        return G

    constructions = {
        ( 36,  14,  4,  6): [Graph,('c~rLDEOcKTPO`U`HOIj@MWFLQFAaRIT`HIWqPsQQJ'+
          'DXGLqYM@gRLAWLdkEW@RQYQIErcgesClhKefC_ygSGkZ`OyHETdK[?lWStCapVgKK')],
        ( 50,   7,  0,  1): [HoffmanSingletonGraph],
        ( 56,  10,  0,  2): [SimsGewirtzGraph],
        ( 77,  16,   0,  4): [M22Graph],
        ( 81,  50,  31, 30): [SRG_81_50_31_30],
        (100,  22,   0,  6): [HigmanSimsGraph],
        (100,  44,  18, 20): [SRG_100_44_18_20],
        (100,  45,  20, 20): [SRG_100_45_20_20],
        (105,  32,   4, 12): [SRG_105_32_4_12],
        (120,  63,  30, 36): [SRG_120_63_30_36],
        (120,  77,  52, 44): [SRG_120_77_52_44],
        (126,  25,   8,  4): [SRG_126_25_8_4],
        (126,  50,  13, 24): [SRG_126_50_13_24],
        (144,  39,   6, 12): [SRG_144_39_6_12],
        (162,  56,  10, 24): [LocalMcLaughlinGraph],
        (175,  72,  20, 36): [SRG_175_72_20_36],
        (176,  49,  12, 14): [SRG_176_49_12_14],
        (176, 105,  68, 54): [SRG_176_105_68_54],
        (196,  91,  42, 42): [SRG_196_91_42_42],
        (210,  99,  48, 45): [SRG_210_99_48_45],
        (220,  84,  38, 28): [SRG_220_84_38_28],
        (231,  30,   9,  3): [CameronGraph],
        (243, 110,  37, 60): [SRG_243_110_37_60],
        (243, 220, 199,200): [SRG_243_220_199_200],
        (253, 140,  87, 65): [SRG_253_140_87_65],
        (256, 170, 114,110): [SRG_256_170_114_110],
        (256, 187, 138,132): [SRG_256_187_138_132],
        (256, 153,  92, 90): [SRG_256_153_92_90],
        (275, 112,  30, 56): [McLaughlinGraph],
        (276, 140,  58, 84): [SRG_276_140_58_84],
        (280, 117, 44,  52): [SRG_280_117_44_52],
        (280, 135,  70, 60): [SRG_280_135_70_60],
        (416, 100,  36, 20): [SRG_416_100_36_20],
        (512, 219, 106, 84): [SRG_512_219_106_84],
        (512,  73,  12, 10): [SRG_512_73_12_10],
        (512, 315, 202,180): [SRG_512_315_202_180],
        (560, 208,  72, 80): [SRG_560_208_72_80],
        (625, 364, 213,210): [SRG_625_364_213_210],
        (625, 416, 279,272): [SRG_625_416_279_272],
        (625, 468, 353,342): [SRG_625_468_353_342],
        (729, 336, 153,156): [SRG_729_336_153_156],
        (729, 616, 523,506): [SRG_729_616_523_506],
        (729, 420, 243,240): [SRG_729_420_243_240],
        (729, 448, 277,272): [SRG_729_448_277_272],
        (729, 560, 433,420): [SRG_729_560_433_420],
        (729, 476, 313,306): [SRG_729_476_313_306],
        (729, 532, 391,380): [SRG_729_532_391_380],
        (784, 243,  82, 72): [MathonStronglyRegularGraph, 0],
        (784, 270, 98, 90):  [MathonStronglyRegularGraph, 1],
        (784, 297, 116, 110):[MathonStronglyRegularGraph, 2],
        (1024,825, 668,650): [SRG_1024_825_668_650],
        (1288,792, 476,504): [SRG_1288_792_476_504],
        (1782,416, 100, 96): [SuzukiGraph],
    }

    if params in constructions:
        val = constructions[params]
        return True if existence else check_srg(val[0](*val[1:]))
    if params_complement in constructions:
        val = constructions[params_complement]
        return True if existence else check_srg(val[0](*val[1:]).complement())

    test_functions = [is_paley, is_johnson,
                      is_orthogonal_array_block_graph,
                      is_steiner, is_affine_polar,
                      is_goethals_seidel,
                      is_orthogonal_polar,
                      is_NOodd, is_NOperp_F5, is_NO_F2, is_NO_F3, is_NU,
                      is_unitary_polar, is_unitary_dual_polar, is_GQqmqp,
                      is_RSHCD,
                      is_twograph_descendant_of_srg,
                      is_taylor_twograph_srg,
                      is_switch_OA_srg,
                      is_polhill,
                      is_mathon_PC_srg,
                      is_switch_skewhad]

    # Going through all test functions, for the set of parameters and its
    # complement.
    for f in test_functions:
        if f(*params):
            if existence:
                return True
            ans = f(*params)
            return check_srg(ans[0](*ans[1:]))
        if f(*params_complement):
            if existence:
                return True
            ans = f(*params_complement)
            return check_srg(ans[0](*ans[1:]).complement())

    # From now on, we have no idea how to build the graph.
    #
    # We try to return the most appropriate error message.

    global _brouwer_database
    brouwer_data = _brouwer_database.get(params,None)

    if brouwer_data is not None:
        if brouwer_data['status'] == 'impossible':
            if existence:
                return False
            raise EmptySetError("Andries Brouwer's database reports that no "+
                                str((v,k,l,mu))+"-strongly regular graph exists. "+
                                "Comments: "+brouwer_data['comments'].encode('ascii','ignore'))

        if brouwer_data['status'] == 'open':
            if existence:
                return Unknown
            raise RuntimeError(("Andries Brouwer's database reports that no "+
                                "({},{},{},{})-strongly regular graph is known "+
                                "to exist.\nComments: ").format(v,k,l,mu)
                               +brouwer_data['comments'].encode('ascii','ignore'))

        if brouwer_data['status'] == 'exists':
            if existence:
                return True
            raise RuntimeError(("Andries Brouwer's database claims that such a "+
                                "({},{},{},{})-strongly regular graph exists, but "+
                                "Sage does not know how to build it. If *you* do, "+
                                "please get in touch with us on sage-devel!\n"+
                                "Comments: ").format(v,k,l,mu)
                               +brouwer_data['comments'].encode('ascii','ignore'))
    if existence:
        return Unknown
    raise RuntimeError(("Sage cannot figure out if a ({},{},{},{})-strongly "+
                        "regular graph exists.").format(v,k,l,mu))

def apparently_feasible_parameters(int n):
    r"""
    Return a list of parameters `(v,k,\lambda,\mu)` which are a-priori feasible.

    Note that some of those that it returns may also be infeasible for more
    involved reasons.

    INPUT:

    - ``n`` (integer) -- return all a-priori feasible tuples `(v,k,\lambda,\mu)`
      for `v<n`

    EXAMPLE:

    All sets of parameters with `v<20` which pass basic arithmetic tests are
    feasible::

        sage: from sage.graphs.strongly_regular_db import apparently_feasible_parameters
        sage: small_feasible = apparently_feasible_parameters(20); small_feasible
        {(5, 2, 0, 1),
         (9, 4, 1, 2),
         (10, 3, 0, 1),
         (10, 6, 3, 4),
         (13, 6, 2, 3),
         (15, 6, 1, 3),
         (15, 8, 4, 4),
         (16, 5, 0, 2),
         (16, 6, 2, 2),
         (16, 9, 4, 6),
         (16, 10, 6, 6),
         (17, 8, 3, 4)}
        sage: all(graphs.strongly_regular_graph(*x,existence=True) for x in small_feasible)
        True

    But that becomes wrong for `v<60` (because of the non-existence of a
    `(49,16,3,6)`-strongly regular graph)::

        sage: small_feasible = apparently_feasible_parameters(60)
        sage: all(graphs.strongly_regular_graph(*x,existence=True) for x in small_feasible)
        False

    """
    cdef int v,k,l,mu
    feasible = set()
    for v in range(n):
        for k in range(1,v-1):
            for l in range(k-1):
                mu = k*(k-l-1)//(v-k-1)
                if seems_feasible(v,k,l,mu):
                    feasible.add((v,k,l,mu))
    return feasible

cdef load_brouwer_database():
    r"""
    Loads Andries Brouwer's database into _brouwer_database.
    """
    global _brouwer_database
    if _brouwer_database is not None:
        return
    import json

    from sage.env import SAGE_SHARE
    with open(SAGE_SHARE+"/graphs/brouwer_srg_database.json",'r') as datafile:
        _brouwer_database = {(v,k,l,mu):{'status':status,'comments':comments}
                             for (v,k,l,mu,status,comments) in json.load(datafile)}

def _check_database():
    r"""
    Checks the coherence of Andries Brouwer's database with Sage.

    The function also outputs some statistics on the database.

    EXAMPLE::

        sage: from sage.graphs.strongly_regular_db import _check_database
        sage: _check_database() # long time
        Sage cannot build a (45   22   10   11  ) that exists. Comment from Brouwer's database: <a href="srgtabrefs.html#Mathon78">Mathon</a>; 2-graph*
        ...
        In Andries Brouwer's database:
        - 448 impossible entries
        - 2950 undecided entries
        - 1140 realizable entries (Sage misses ... of them)

    """
    global _brouwer_database
    load_brouwer_database()

    # Check that all parameters detected as infeasible are actually infeasible
    # in Brouwer's database, for a test that was implemented.
    for params in set(_brouwer_database).difference(apparently_feasible_parameters(1301)):
        if _brouwer_database[params]['status'] != "impossible":
            raise RuntimeError("Brouwer's db does not seem to know that {} in unfeasible".format(params))
        comment = _brouwer_database[params]['comments']
        if ('Krein'    in comment or
            'Absolute' in comment or
            'Conf'     in comment or
            'mu=1'     in comment or
            '&mu;=2'   in comment):
            continue
        raise RuntimeError("We detected that {} was unfeasible, but maybe we should not have".format(params))

    # We empty the global database, to be sure that strongly_regular_graph does
    # not use its data to answer.
    _brouwer_database, saved_database = {}, _brouwer_database

    cdef int missed = 0
    for params,dic in sorted(saved_database.items()):
        sage_answer = strongly_regular_graph(*params,existence=True)
        if dic['status'] == 'open':
            if sage_answer:
                print "Sage can build a {}, Brouwer's database cannot".format(params)
            assert sage_answer is not False
        elif dic['status'] == 'exists':
            if sage_answer is not True:
                print (("Sage cannot build a ({:<4} {:<4} {:<4} {:<4}) that exists. "+
                       "Comment from Brouwer's database: ").format(*params)
                       +dic['comments'].encode('ascii','ignore'))
                missed += 1
            assert sage_answer is not False
        elif dic['status'] == 'impossible':
            assert sage_answer is not True
        else:
            assert False # must not happen

    status = [x['status'] for x in saved_database.values()]
    print "\nIn Andries Brouwer's database:"
    print "- {} impossible entries".format(status.count('impossible'))
    print "- {} undecided entries".format(status.count('open'))
    print "- {} realizable entries (Sage misses {} of them)".format(status.count('exists'),missed)

    # Reassign its value to the global database
    _brouwer_database = saved_database
