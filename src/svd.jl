"""
Calculates the SVD deomposition of a matrix by employing
a divide and conquer approach.
Returns a `SVD` factorization object.
"""
gesdd(x) = gesdd!(copy(x))
"""
Same as `gesdd` but saves space by overwriting the input matrix.
"""
function gesdd!(x)
  u,s,vt = LinearAlgebra.LAPACK.gesdd!('A', x)
  SVD(u,s,vt)
end


"""
Calculates the SVD deomposition of a matrix.
Returns a `SVD` factorization object.
"""
gesvd(x) = gesvd!(copy(x))
"""
Same as `gesvd` but saves space by overwriting the input matrix.
"""
function gesvd!(x)
  u,s,vt = LinearAlgebra.LAPACK.gesvd!('A', 'A', x)
  SVD(u,s,vt)
end


"""
Calculates the SVD deomposition of a matrix by using the
Jacobi method. Returns a `SVD` factorization object.
"""
gesvj(x) = gesvj!(copy(x))
"""
Same as `gesvj` but saves space by overwriting the input matrix.
"""
function gesvj!(x)
  JacobiSVD.jsvd!(x)
end


"""
Calculates the SVD deomposition of a matrix in a type generic manner.
Can for example be used with a `Matrix{BigFloat}`.
Returns a `SVD` factorization object.
"""
genericsvd(x) = genericsvd!(copy(x))
"""
Same as `genericsvd` but saves space by overwriting the input matrix.
"""
function genericsvd!(x)
  GenericSVD.svd!(x)
end




# extra operations for SVD factorizations
"""
    svd_mult(A::SVD, B::SVD) -> SVD

Stabilized multiplication of two SVD decompositions.
Returns a `SVD` factorization object.
"""
function svd_mult(A::SVD, B::SVD)
    mat = A.Vt * B.U
    lmul!(Diagonal(A.S), mat)
    rmul!(mat, Diagonal(B.S))
    F = udv!(mat)
    SVD(A.U * F.U, F.S, F.Vt * B.Vt)
end


myinv(F::SVD) = (Diagonal(1 ./ F.S) * F.Vt)' * F.U'


# """
#     *(A::SVD, B::SVD)

# Stabilized multiplication of two SVD decompositions.

# (Type piracy if `LinearAlgebra` defines `*` for `SVD`s in the future!)
# """
# function Base.:*(A::SVD, B::SVD)
#     mat = A.Vt * B.U
#     lmul!(Diagonal(A.S), mat)
#     rmul!(mat, Diagonal(B.S))
#     F = udv!(mat)
#     (A.U * F.U) * Diagonal(F.S) * (F.Vt * B.Vt)
# end










##############################################################
#
#                   SVD / USVt
#
##############################################################

"""
    svd_inv_one_plus(F::SVD) -> SVD

Stabilized calculation of [1 + USVt]^(-1):

  * Use one intermediate SVD decomposition.

Options for preallocation via keyword arguments:

  * None (yet)
"""
function svd_inv_one_plus(F::SVD; svdalg = svd!)
  # TODO: optimize
  U, S, V = F
  t = U' * V
  t += Diagonal(S)
  u, s, v = svdalg(t)
  a = V * v
  b = Diagonal(1 ./ s)
  c = inv(U * u)
  SVD(a, b, c)
end


"""
    inv_one_plus!(res, F::SVD) -> res

Stabilized calculation of [1 + USVt]^(-1):

  * Use one intermediate SVD decomposition.

Writes the result into `res`.

See `svd_inv_one_plus` for preallocation options.
"""
function inv_one_plus!(res, F::SVD; kwargs...)
  M = svd_inv_one_plus(F; kwargs...)
  rmul!(M.U, Diagonal(M.S))
  mul!(res, M.U, M.Vt)
  res
end


"""
    inv_one_plus(F::SVD) -> AbstractMatrix

Stabilized calculation of [1 + USVt]^(-1):

  * Use one intermediate SVD decomposition.

See `svd_inv_one_plus` for preallocation options.
"""
function inv_one_plus(F::SVD; kwargs...)
  res = similar(F.U)
  inv_one_plus!(res, F; kwargs...)
  res
end



"""
    svd_inv_one_plus_loh(F::SVD) -> SVD

Stabilized calculation of [1 + USVt]^(-1):

  * Separate scales larger and smaller than unity
  * Use two intermediate SVD decompositions.

Options for preallocation via keyword arguments:

  * `l = similar(F.U)`
  * `r = similar(F.U)`
  * `Dp = similar(F.D)`
  * `Dm = similar(F.D)`
"""
function svd_inv_one_plus_loh(F::SVD; svdalg = svd!, Sp = similar(F.S), Sm = similar(F.S), l = similar(F.V), r = similar(F.U))
  U, S, V = F

  copyto!(l, V)
  copyto!(r, U)

  Sp .= max.(S, 1)
  Sm .= min.(S, 1)

  Sp .\= 1 # Sp now Spinv!!!

  rmul!(l, Diagonal(Sp))
  rmul!(r, Diagonal(Sm))

  M = svdalg(l + r)
  m = inv(M)
  lmul!(Diagonal(Sp), m)
  u, s, v = svdalg(m)
  mul!(m, V, u)

  SVD(m, s, v')
end


"""
  inv_one_plus_loh!(res, F::SVD) -> res

Stabilized calculation of [1 + USVt]^(-1):

  * Separate scales larger and smaller than unity
  * Use two intermediate SVD decompositions.

Writes the result into `res`.

See `svd_inv_one_plus_loh` for preallocation options.
"""
function inv_one_plus_loh!(res, F::SVD; kwargs...)
  M = svd_inv_one_plus_loh(F; kwargs...)
  rmul!(M.U, Diagonal(M.S))
  mul!(res, M.U, M.Vt)
  res
end


"""
  inv_one_plus_loh(F::SVD) -> AbstractMatrix

Stabilized calculation of [1 + USVt]^(-1):

  * Separate scales larger and smaller than unity
  * Use two intermediate SVD decompositions.

See `svd_inv_one_plus_loh` for preallocation options.
"""
function inv_one_plus_loh(F::SVD; kwargs...)
  res = similar(F.U)
  inv_one_plus_loh!(res, F; kwargs...)
end












"""
    svd_inv_sum_loh(A::SVD, B::SVD) -> SVD

Stabilized calculation of [UaSaVta + UbSbVtb]^(-1):

  * Separate scales larger and smaller than unity
  * Use two intermediate SVD decompositions.

Options for preallocations via keyword arguments:

  * None (yet)

"""
function svd_inv_sum_loh(A::SVD, B::SVD; svdalg = svd!)
    Ua, Sa, Va = A
    Ub, Sb, Vb = B
    
    d = length(Sa)
    
    Sap = max.(Sa,1.)
    Sam = min.(Sa,1.)
    Sbp = max.(Sb,1.)
    Sbm = min.(Sb,1.)

    mat1 = Va' * Vb
    for j in 1:d, k in 1:d
        mat1[j,k]=mat1[j,k] * Sam[j]/Sbp[k]
    end

    mat2 = adjoint(Ua) * Ub
    for j in 1:d, k in 1:d
        mat2[j,k]=mat2[j,k] * Sbm[k]/Sap[j]
    end
    
    mat1 = mat1 + mat2
    
    M = svdalg(mat1)
    mat1 = inv(M)

    for j in 1:d, k in 1:d
        mat1[j,k]=mat1[j,k] / Sbp[j] / Sap[k]
    end

    u, s, v = svdalg(mat1)
    mul!(mat1, Vb, u)
    mul!(mat2, v', adjoint(Ua))

    SVD(mat1, s, mat2)
end


"""
    inv_sum_loh!(res, A::SVD, B::SVD) -> res

Stabilized calculation of [UaSaVta + UbSbVtb]^(-1):

  * Separate scales larger and smaller than unity
  * Use two intermediate SVD decompositions.

Writes the result into `res`.

See `svd_inv_sum_loh` for preallocation options.
"""
function inv_sum_loh!(res, A::SVD, B::SVD; kwargs...)
  M = svd_inv_sum_loh(A, B; kwargs...)
  rmul!(M.U, Diagonal(M.S))
  mul!(res, M.U, M.Vt)
  res

end

"""
    inv_sum_loh(A::SVD, B::SVD) -> res

Stabilized calculation of [UaSaVta + UbSbVtb]^(-1):

  * Separate scales larger and smaller than unity
  * Use two intermediate SVD decompositions.

See `svd_inv_sum_loh` for preallocation options.
"""
function inv_sum_loh(A::SVD, B::SVD; kwargs...)
  res = similar(A.U)
  inv_sum_loh!(res, A, B; kwargs...)
  res
end