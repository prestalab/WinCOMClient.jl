# dispatch.jl — Dispatch type, ownership, invocation core, COMMember, Base API
# Plus ProgID/CLSID/moniker resolution helpers (Step 3).

using Dates

# ---------------------------------------------------------------------------
# Step 4 — Dispatch type and ownership
# ---------------------------------------------------------------------------
mutable struct Dispatch
    ptr::Ptr{IDispatch}
    name::String                 # user-facing name for repr, mirrors _username_
    dispids::Dict{String, Int32}  # avoid repeated IDispatch::GetIDsOfNames calls
end

function Dispatch(p::Ptr{IDispatch}, name::AbstractString="<unknown>")
    p == C_NULL && throw(ArgumentError("null IDispatch"))
    return Dispatch(p, String(name), Dict{String, Int32}())
end

ptr(d::Dispatch) = getfield(d, :ptr)
Base.isopen(d::Dispatch) = ptr(d) != C_NULL

function Base.close(d::Dispatch)
    if isopen(d)
        Release(ptr(d))
        setfield!(d, :ptr, Ptr{IDispatch}(C_NULL))
        empty!(getfield(d, :dispids))
    end
    return nothing
end

_finalize(d::Dispatch) = close(d)

# Single place that creates an owned wrapper and attaches the finalizer.
# p must already be AddRef'd exactly once on behalf of the wrapper.
function wrap_dispatch(p::Ptr{IDispatch}, name::AbstractString="<unknown>")
    d = Dispatch(p, name)
    finalizer(_finalize, d)
    return d
end

# ---------------------------------------------------------------------------
# Step 3 — ProgID / CLSID / moniker resolution helpers
# ---------------------------------------------------------------------------
function progid_to_clsid(progid::AbstractString)::CLSID
    data = transcode(WCHAR, String(progid))
    push!(data, 0)   # NUL terminator
    clsid = Ref{CLSID}()
    GC.@preserve data begin
        hr = CLSIDFromProgID(pointer(data), clsid)
    end
    check(hr, "CLSIDFromProgID($progid)")
    return clsid[]
end

function clsid_from_string(s::AbstractString)::CLSID
    data = transcode(WCHAR, String(s))
    push!(data, 0)
    clsid = Ref{CLSID}()
    GC.@preserve data begin
        hr = CLSIDFromString(pointer(data), clsid)
    end
    check(hr, "CLSIDFromString($s)")
    return clsid[]
end

function iid_from_string(s::AbstractString)::IID
    data = transcode(WCHAR, String(s))
    push!(data, 0)
    iid = Ref{IID}()
    GC.@preserve data begin
        hr = IIDFromString(pointer(data), iid)
    end
    check(hr, "IIDFromString($s)")
    return iid[]
end

# GetActiveObject -> IDispatch; returns C_NULL if no running instance
function get_active_idispatch(id::Union{AbstractString, GUID})::Ptr{IDispatch}
    clsid = id isa AbstractString ? progid_to_clsid(id) : id
    punk = Ref{Ptr{Cvoid}}(C_NULL)
    hr = GetActiveObject(Ref(clsid), C_NULL, punk)
    if hr < 0
        return C_NULL   # no running instance; caller falls back to CoCreateInstance
    end
    # QI for IDispatch
    ppv = Ref{Ptr{Cvoid}}(C_NULL)
    hr = QueryInterface(reinterpret(Ptr{IUnknown}, punk[]), Ref(IID_IDispatch), ppv)
    Release(reinterpret(Ptr{IUnknown}, punk[]))  # release the IUnknown
    if hr < 0
        return C_NULL
    end
    return reinterpret(Ptr{IDispatch}, ppv[])
end

# CoCreateInstance -> IDispatch (refcount=1)
function create_instance(clsid::CLSID, clsctx::UInt32)::Ptr{IDispatch}
    ppv = Ref{Ptr{Cvoid}}(C_NULL)
    hr = CoCreateInstance(Ref(clsid), C_NULL, clsctx, Ref(IID_IDispatch), ppv)
    check(hr, "CoCreateInstance")
    return reinterpret(Ptr{IDispatch}, ppv[])
end

# Moniker bind: MkParseDisplayName + BindToObject -> IDispatch
function moniker_bind(path::AbstractString)::Ptr{IDispatch}
    pbc = Ref{Ptr{Cvoid}}(C_NULL)
    check(CreateBindCtx(UInt32(0), pbc), "CreateBindCtx")
    data = transcode(WCHAR, String(path))
    push!(data, 0)
    pmk = Ref{Ptr{Cvoid}}(C_NULL)
    eaten = Ref{UInt32}(0)
    GC.@preserve data begin
        hr = MkParseDisplayName(pbc[], pointer(data), eaten, pmk)
    end
    if hr < 0
        # Release bind ctx before throwing
        Release(reinterpret(Ptr{IUnknown}, pbc[]))
        throw(COMException(hr, "MkParseDisplayName($path)"))
    end
    # BindToObject via IMoniker vtable slot 4
    ppv = Ref{Ptr{Cvoid}}(C_NULL)
    hr = BindToObject(pmk[], pbc[], C_NULL, Ref(IID_IDispatch), ppv)
    # Release moniker and bind ctx
    Release(reinterpret(Ptr{IUnknown}, pmk[]))
    Release(reinterpret(Ptr{IUnknown}, pbc[]))
    check(hr, "BindToObject($path)")
    return reinterpret(Ptr{IDispatch}, ppv[])
end

# ---------------------------------------------------------------------------
# Step 5 — Invocation core
# ---------------------------------------------------------------------------

# getids: resolve a member name to a DISPID
function getids(d::Dispatch, name::AbstractString)::Int32
    isopen(d) || throw(ArgumentError("COM object is closed"))
    key = String(name)
    cache = getfield(d, :dispids)
    return get!(cache, key) do
        data = transcode(WCHAR, key)
        push!(data, 0)
        names = Ref{Ptr{WCHAR}}(C_NULL)
        GC.@preserve data begin
            names[] = pointer(data)
            dispid = Ref{Int32}(0)
            hr = GetIDsOfNames(ptr(d), names, UInt32(1), DISPATCH_LCID, dispid)
            return hr < 0 ? DISPID_UNKNOWN : dispid[]
        end
    end
end

# invoke: the core IDispatch::Invoke wrapper
# args is an ordered iterable of Julia values (positional, left-to-right)
function invoke(d::Dispatch, dispid::Int32, wFlags::UInt16, args)::Any
    isopen(d) || throw(ArgumentError("COM object is closed"))
    n = length(args)
    argrefs = [Ref{VARIANT}() for _ in 1:n]
    initialized = 0
    ref_result = Ref{VARIANT}()
    VariantInit(ref_result)

    try
        for i in 1:n
            VariantInit(argrefs[i])
            initialized = i
            to_variant(args[i], argrefs[i])
        end

        named = if (wFlags & (DISPATCH_PROPERTYPUT | DISPATCH_PROPERTYPUTREF)) != 0
            Int32[DISPID_PROPERTYPUT]
        else
            Int32[]
        end
        revargs = Vector{VARIANT}(undef, n)
        for i in 1:n
            revargs[n - i + 1] = argrefs[i][]
        end

        dp = DISPPARAMS(
            isempty(revargs) ? C_NULL : pointer(revargs),
            isempty(named) ? C_NULL : pointer(named),
            UInt32(n),
            UInt32(length(named)),
        )
        ref_excep = Ref{EXCEPINFO}(
            EXCEPINFO(0, 0, C_NULL, C_NULL, C_NULL, 0, C_NULL, C_NULL, Clong(0))
        )
        ref_argerr = Ref{UInt32}(0)
        dpref = Ref(dp)
        hr = GC.@preserve revargs named begin
            Invoke(ptr(d), dispid, wFlags, dpref, ref_result, ref_excep, ref_argerr)
        end

        if hr < 0
            ex = ref_excep[]
            desc = bstr_to_string(ex.bstrDescription)
            src = bstr_to_string(ex.bstrSource)
            ex.bstrDescription != C_NULL && SysFreeString(ex.bstrDescription)
            ex.bstrSource != C_NULL && SysFreeString(ex.bstrSource)
            ex.bstrHelpFile != C_NULL && SysFreeString(ex.bstrHelpFile)
            throw(COMException(hr, isempty(desc) ? "Invoke failed" : desc, src))
        end

        return from_variant(ref_result[])
    finally
        for i in 1:initialized
            VariantClear(argrefs[i])
        end
        VariantClear(ref_result)
    end
end

# put: propertyput wrapper
function put(d::Dispatch, name::AbstractString, v)
    dispid = getids(d, name)
    if dispid == DISPID_UNKNOWN
        throw(ErrorException("COM: no member '$name' on $(d.name)"))
    end
    flags = v isa Dispatch ? DISPATCH_PROPERTYPUTREF : DISPATCH_PROPERTYPUT
    invoke(d, dispid, flags, (v,))
    return nothing
end

# ---------------------------------------------------------------------------
# COMMember — lazy member handle
# ---------------------------------------------------------------------------
struct COMMember
    d::Dispatch
    name::String
    dispid::Int32
end

# Explicit property read (alias for zero-arg invoke)
value(m::COMMember) = m()

# Invoke the member with args
function (m::COMMember)(args...)
    return invoke(m.d, m.dispid, DISPATCH_METHOD | DISPATCH_PROPERTYGET, collect(Any, args))
end

# ---------------------------------------------------------------------------
# Base API — getproperty / setproperty!
# ---------------------------------------------------------------------------
function Base.getproperty(d::Dispatch, s::Symbol)
    if s === :ptr || s === :name || s === :dispids
        return getfield(d, s)
    end
    name = String(s)
    dispid = getids(d, name)
    if dispid == DISPID_UNKNOWN
        throw(ErrorException("COM: no member '$s' on $(d.name)"))
    end
    return COMMember(d, name, dispid)
end

function Base.getproperty(m::COMMember, s::Symbol)
    if s === :d || s === :name || s === :dispid
        return getfield(m, s)
    end
    # Chain: invoke parent with zero args to get the Dispatch, then .s on it
    return getproperty(value(m), s)
end

function Base.setproperty!(d::Dispatch, s::Symbol, v)
    if s === :ptr || s === :name
        return setfield!(d, s, v)
    end
    put(d, String(s), v)
    return v
end

function Base.setproperty!(m::COMMember, s::Symbol, v)
    setproperty!(value(m), s, v)
    return v
end

# ---------------------------------------------------------------------------
# Base API — show
# ---------------------------------------------------------------------------
function Base.show(io::IO, d::Dispatch)
    return print(io, "<COM $(d.name)>")
end
function Base.show(io::IO, m::COMMember)
    return print(io, "<COM.$(m.name)>")
end

# ---------------------------------------------------------------------------
# Base API — length (Count property)
# ---------------------------------------------------------------------------
function Base.length(d::Dispatch)
    dispid = getids(d, "Count")
    if dispid == DISPID_UNKNOWN
        throw(ErrorException("COM: no Count on $(d.name)"))
    end
    return Int(invoke(d, dispid, DISPATCH_METHOD | DISPATCH_PROPERTYGET, Any[]))
end

# ---------------------------------------------------------------------------
# Base API — iteration via DISPID_NEWENUM / IEnumVARIANT
# ---------------------------------------------------------------------------
function Base.iterate(d::Dispatch, state=nothing)
    if state === nothing
        # First call: get the IEnumVARIANT
        result = invoke(d, DISPID_NEWENUM, DISPATCH_METHOD | DISPATCH_PROPERTYGET, Any[])
        # result is either a Dispatch (VT_DISPATCH wrapped) or raw Ptr{IUnknown}
        enumptr = if result isa Dispatch
            # QI for IEnumVARIANT
            ppv = Ref{Ptr{Cvoid}}(C_NULL)
            hr = QueryInterface(ptr(result), Ref(IID_IEnumVARIANT), ppv)
            if hr < 0
                throw(COMException(hr, "QueryInterface(IID_IEnumVARIANT)"))
            end
            reinterpret(Ptr{IEnumVARIANT}, ppv[])
        elseif result isa Ptr{IUnknown}
            ppv = Ref{Ptr{Cvoid}}(C_NULL)
            hr = QueryInterface(result, Ref(IID_IEnumVARIANT), ppv)
            if hr < 0
                throw(COMException(hr, "QueryInterface(IID_IEnumVARIANT)"))
            end
            reinterpret(Ptr{IEnumVARIANT}, ppv[])
        else
            throw(ErrorException("COM: _NewEnum did not return IUnknown/IDispatch"))
        end
        return _enum_next(enumptr)
    else
        return _enum_next(state)
    end
end

function _enum_next(enumptr::Ptr{IEnumVARIANT})
    elt = Ref{VARIANT}()
    VariantInit(elt)
    fetched = Ref{UInt32}(0)
    hr = Next(enumptr, UInt32(1), elt, fetched)
    if hr == S_FALSE || fetched[] == 0
        Release(enumptr)
        VariantClear(elt)
        return nothing
    end
    val = from_variant(elt[])
    VariantClear(elt)
    return (val, enumptr)
end

Base.eltype(::Type{Dispatch}) = Any
Base.IteratorSize(::Type{Dispatch}) = Base.SizeUnknown()

# ---------------------------------------------------------------------------
# Base API — getindex / setindex!
# ---------------------------------------------------------------------------
function Base.getindex(d::Dispatch, idx)
    dispid = getids(d, "Item")
    if dispid == DISPID_UNKNOWN
        throw(ErrorException("COM: no Item/enumeration on $(d.name)"))
    end
    return invoke(d, dispid, DISPATCH_METHOD | DISPATCH_PROPERTYGET, Any[idx])
end

function Base.setindex!(d::Dispatch, v, idx...)
    flags = v isa Dispatch ? DISPATCH_PROPERTYPUTREF : DISPATCH_PROPERTYPUT
    invoke(d, DISPID_VALUE, flags, (idx..., v))
    return v
end
