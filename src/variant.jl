# variant.jl — VARIANT <-> Julia conversion
# to_variant(x, v::Ref{VARIANT}) :: Nothing  — fill v with a VARIANT representing x
# from_variant(v::VARIANT) :: Any            — convert a VARIANT to a Julia value

# Zero a VARIANT ref
@inline function _variant_zero!(v::Ref{VARIANT})
    v[] = VARIANT(0, 0, 0, 0, (UInt64(0), UInt64(0)))
    return v
end

# ---------------------------------------------------------------------------
# to_variant — Julia value -> VARIANT
# ---------------------------------------------------------------------------
function to_variant(x::Bool, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_BOOL, 0, 0, 0, (UInt64(x ? 0xFFFF : 0), UInt64(0)))
    return nothing
end

function to_variant(x::Int8, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_I1, 0, 0, 0, (UInt64(reinterpret(UInt8, x)), UInt64(0)))
    return nothing
end

function to_variant(x::Int16, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_I2, 0, 0, 0, (UInt64(reinterpret(UInt16, x)), UInt64(0)))
    return nothing
end

function to_variant(x::Int32, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_I4, 0, 0, 0, (UInt64(reinterpret(UInt32, x)), UInt64(0)))
    return nothing
end

function to_variant(x::Int64, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_I8, 0, 0, 0, (reinterpret(UInt64, x), UInt64(0)))
    return nothing
end

function to_variant(x::UInt8, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_UI1, 0, 0, 0, (UInt64(x), UInt64(0)))
    return nothing
end

function to_variant(x::UInt16, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_UI2, 0, 0, 0, (UInt64(x), UInt64(0)))
    return nothing
end

function to_variant(x::UInt32, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_UI4, 0, 0, 0, (UInt64(x), UInt64(0)))
    return nothing
end

function to_variant(x::UInt64, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_UI8, 0, 0, 0, (x, UInt64(0)))
    return nothing
end

function to_variant(x::Float32, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_R4, 0, 0, 0, (UInt64(reinterpret(UInt32, x)), UInt64(0)))
    return nothing
end

function to_variant(x::Float64, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_R8, 0, 0, 0, (reinterpret(UInt64, x), UInt64(0)))
    return nothing
end

function to_variant(x::AbstractString, v::Ref{VARIANT})
    _variant_zero!(v)
    bstr = bstr_alloc(x)
    v[] = VARIANT(VT_BSTR, 0, 0, 0, (reinterpret(UInt64, bstr), UInt64(0)))
    return nothing
end

function to_variant(x::Dispatch, v::Ref{VARIANT})
    _variant_zero!(v)
    # COM ownership: AddRef the outgoing dispatch
    AddRef(ptr(x))
    v[] = VARIANT(VT_DISPATCH, 0, 0, 0, (reinterpret(UInt64, ptr(x)), UInt64(0)))
    return nothing
end

function to_variant(::Nothing, v::Ref{VARIANT})
    _variant_zero!(v)
    v[] = VARIANT(VT_NULL, 0, 0, 0, (UInt64(0), UInt64(0)))
    return nothing
end

function to_variant(::Missing, v::Ref{VARIANT})
    _variant_zero!(v)
    code = UInt64(reinterpret(UInt32, DISP_E_PARAMNOTFOUND))
    v[] = VARIANT(VT_ERROR, 0, 0, 0, (code, UInt64(0)))
    return nothing
end

# AbstractVector -> SAFEARRAY (minimal: 1-D)
function to_variant(x::AbstractVector, v::Ref{VARIANT})
    _variant_zero!(v)
    n = length(x)
    # Determine element VARTYPE from first element; default VT_VARIANT for mixed
    elemVt = if n > 0
        el = first(x)
        _julia_to_vt(el)
    else
        VT_VARIANT
    end
    psa = SafeArrayCreateVector(elemVt, Int32(0), UInt32(n))
    psa == C_NULL && error("SafeArrayCreateVector failed")
    for i in 1:n
        idx = Int32[i - 1]
        if elemVt == VT_VARIANT
            eltref = Ref{VARIANT}()
            VariantInit(eltref)
            to_variant(x[i], eltref)
            SafeArrayPutElement(psa, pointer(idx), pointer_from_objref(eltref))
            VariantClear(eltref)
        else
            eltref = Ref{VARIANT}()
            VariantInit(eltref)
            to_variant(x[i], eltref)
            # For non-VARIANT safearrays, copy the value bytes directly
            SafeArrayPutElement(psa, pointer(idx), pointer_from_objref(eltref) + 8)  # skip vt header to val
            VariantClear(eltref)
        end
    end
    v[] = VARIANT(VT_ARRAY | elemVt, 0, 0, 0, (reinterpret(UInt64, psa), UInt64(0)))
    return nothing
end

# Fallback: try converting via string or throw
function to_variant(x, v::Ref{VARIANT})
    return error("to_variant: unsupported Julia type $(typeof(x)) for COM VARIANT")
end

# Helper: map Julia value to VARTYPE
_julia_to_vt(::Bool) = VT_BOOL
_julia_to_vt(::Integer) = VT_I4
_julia_to_vt(::AbstractFloat) = VT_R8
_julia_to_vt(::AbstractString) = VT_BSTR
_julia_to_vt(::Dispatch) = VT_DISPATCH
_julia_to_vt(::Nothing) = VT_NULL
_julia_to_vt(::Missing) = VT_ERROR
_julia_to_vt(_) = VT_VARIANT

# ---------------------------------------------------------------------------
# from_variant — VARIANT -> Julia value
# ---------------------------------------------------------------------------
function from_variant(v::VARIANT)::Any
    vt = v.vt
    # Strip VT_BYREF for handling (we don't produce byref, but be safe)
    base_vt = vt & ~VT_BYREF

    if base_vt == VT_EMPTY || base_vt == VT_NULL
        return nothing
    elseif base_vt == VT_I2
        return reinterpret(Int16, UInt16(v.val[1] & 0xFFFF))
    elseif base_vt == VT_I4
        return reinterpret(Int32, UInt32(v.val[1] & 0xFFFFFFFF))
    elseif base_vt == VT_I8
        return reinterpret(Int64, v.val[1])
    elseif base_vt == VT_I1
        return reinterpret(Int8, UInt8(v.val[1] & 0xFF))
    elseif base_vt == VT_UI1
        return UInt8(v.val[1] & 0xFF)
    elseif base_vt == VT_UI2
        return UInt16(v.val[1] & 0xFFFF)
    elseif base_vt == VT_UI4
        return UInt32(v.val[1] & 0xFFFFFFFF)
    elseif base_vt == VT_UI8
        return v.val[1]
    elseif base_vt == VT_INT
        return reinterpret(Int32, UInt32(v.val[1] & 0xFFFFFFFF))
    elseif base_vt == VT_UINT
        return UInt32(v.val[1] & 0xFFFFFFFF)
    elseif base_vt == VT_R4
        return reinterpret(Float32, UInt32(v.val[1] & 0xFFFFFFFF))
    elseif base_vt == VT_R8
        return reinterpret(Float64, v.val[1])
    elseif base_vt == VT_BOOL
        return Bool((v.val[1] & 0xFFFF) != 0)
    elseif base_vt == VT_BSTR
        p = reinterpret(Ptr{Cvoid}, v.val[1])
        return bstr_to_string(p)
    elseif base_vt == VT_DISPATCH
        p = reinterpret(Ptr{IDispatch}, v.val[1])
        p == Ptr{IDispatch}(0) && return nothing
        # AddRef so the wrapper's ref survives the caller's VariantClear
        AddRef(p)
        return wrap_dispatch(p, "<dispatch>")
    elseif base_vt == VT_UNKNOWN
        p = reinterpret(Ptr{IUnknown}, v.val[1])
        p == Ptr{IUnknown}(0) && return nothing
        # Try QI for IDispatch
        ppv = Ref{Ptr{Cvoid}}(C_NULL)
        hr = QueryInterface(p, Ref(IID_IDispatch), ppv)
        if hr >= 0 && ppv[] != C_NULL
            # QI gave +1 on IDispatch; let VariantClear release the variant's IUnknown ref.
            # Do NOT Release(p) here — that would drop the object before VariantClear.
            return wrap_dispatch(reinterpret(Ptr{IDispatch}, ppv[]), "<dispatch>")
        else
            # AddRef so the raw pointer survives the caller's VariantClear
            AddRef(p)
            return p  # rare: return raw IUnknown pointer
        end
    elseif base_vt == VT_DATE
        # COM DATE = days since 1899-12-30 as Float64
        dt = reinterpret(Float64, v.val[1])
        day = floor(Int, dt)
        frac = dt - day
        base = DateTime(1899, 12, 30)
        return base + Day(day) + Microsecond(round(Int, frac * 86400 * 1_000_000))
    elseif base_vt == VT_ERROR
        return missing
    elseif base_vt == VT_CY || base_vt == VT_DECIMAL
        # Fallback: convert to VT_R8 via VariantChangeType
        return _variant_to_float(v, base_vt)
    elseif (base_vt & VT_ARRAY) == VT_ARRAY
        return _safearray_to_julia(v, base_vt & ~VT_ARRAY)
    elseif base_vt == VT_RECORD
        throw(COMException(Clong(-1), "VT_RECORD not supported (minimal scope)"))
    else
        throw(
            COMException(
                Clong(-1),
                "unsupported VARTYPE 0x$(uppercase(string(UInt16(base_vt), base=16, pad=4)))",
            ),
        )
    end
end

# CY/DECIMAL fallback: coerce to Float64
function _variant_to_float(v::VARIANT, base_vt::UInt16)::Float64
    src = Ref{VARIANT}(v)
    dst = Ref{VARIANT}()
    VariantInit(dst)
    hr = VariantChangeType(dst, src, UInt16(0), VT_R8)
    if hr < 0
        throw(
            COMException(
                hr,
                "VariantChangeType failed for VARTYPE 0x$(uppercase(string(UInt16(base_vt), base=16, pad=4)))",
            ),
        )
    end
    result = reinterpret(Float64, dst[].val[1])
    VariantClear(dst)
    return result
end

# ---------------------------------------------------------------------------
# SAFEARRAY -> Julia Vector / Matrix
# ---------------------------------------------------------------------------
function _safearray_to_julia(v::VARIANT, elemVt::UInt16)::Any
    psa = reinterpret(Ptr{Cvoid}, v.val[1])
    psa == C_NULL && return nothing
    ndim = SafeArrayGetDim(psa)
    elemsize = SafeArrayGetElemsize(psa)

    if ndim == 1
        lb = Ref{Int32}(0)
        ub = Ref{Int32}(0)
        check(SafeArrayGetLBound(psa, UInt32(1), lb), "SafeArrayGetLBound")
        check(SafeArrayGetUBound(psa, UInt32(1), ub), "SafeArrayGetUBound")
        len = ub[] - lb[] + 1
        result = Vector{Any}(undef, len)
        idx = Ref{Int32}(0)
        for i in 1:len
            idx[] = lb[] + (i - 1)
            elt = _safearray_get_element(psa, idx, elemVt, elemsize)
            result[i] = elt
        end
        return result
    elseif ndim == 2
        lb1 = Ref{Int32}(0)
        ub1 = Ref{Int32}(0)
        lb2 = Ref{Int32}(0)
        ub2 = Ref{Int32}(0)
        check(SafeArrayGetLBound(psa, UInt32(1), lb1), "SafeArrayGetLBound(1)")
        check(SafeArrayGetUBound(psa, UInt32(1), ub1), "SafeArrayGetUBound(1)")
        check(SafeArrayGetLBound(psa, UInt32(2), lb2), "SafeArrayGetLBound(2)")
        check(SafeArrayGetUBound(psa, UInt32(2), ub2), "SafeArrayGetUBound(2)")
        rows = ub1[] - lb1[] + 1
        cols = ub2[] - lb2[] + 1
        result = Matrix{Any}(undef, rows, cols)
        idx = Vector{Int32}(undef, 2)
        for r in 1:rows, c in 1:cols
            idx[1] = lb1[] + (r - 1)
            idx[2] = lb2[] + (c - 1)
            result[r, c] = _safearray_get_element(
                psa, Ref(idx[1], idx[2]), elemVt, elemsize; idx2=pointer(idx)
            )
        end
        return result
    else
        throw(COMException(Clong(-1), "SAFEARRAY with ndim=$ndim not supported (max 2)"))
    end
end

# Get one element from a SAFEARRAY; handles VARIANT and scalar element types
function _safearray_get_element(
    psa::Ptr{Cvoid},
    idx::Ref{Int32},
    elemVt::UInt16,
    elemsize::UInt32;
    idx2::Ptr{Int32}=C_NULL,
)
    # For VARIANT elements, SafeArrayGetElement returns a VARIANT
    if elemVt == VT_VARIANT ||
        elemVt == VT_DISPATCH ||
        elemVt == VT_BSTR ||
        elemVt == VT_UNKNOWN ||
        (elemVt & VT_ARRAY) == VT_ARRAY
        eltvar = Ref{VARIANT}()
        VariantInit(eltvar)
        idxptr = idx2 != C_NULL ? idx2 : pointer(idx)
        hr = SafeArrayGetElement(psa, idxptr, pointer_from_objref(eltvar))
        if hr < 0
            VariantClear(eltvar)
            throw(COMException(hr, "SafeArrayGetElement"))
        end
        val = from_variant(eltvar[])
        VariantClear(eltvar)
        return val
    else
        # Scalar element: read into a buffer, then build a VARIANT and from_variant it
        buf = Vector{UInt8}(undef, max(elemsize, 8))
        idxptr = idx2 != C_NULL ? idx2 : pointer(idx)
        hr = SafeArrayGetElement(psa, idxptr, pointer(buf))
        if hr < 0
            throw(COMException(hr, "SafeArrayGetElement"))
        end
        # Construct a VARIANT with the element's vt and value
        val_u = UInt64(0)
        if elemsize <= 8
            val_u = reinterpret(UInt64, buf)[1]
        end
        eltvar = VARIANT(elemVt, 0, 0, 0, (val_u, UInt64(0)))
        return from_variant(eltvar)
    end
end
