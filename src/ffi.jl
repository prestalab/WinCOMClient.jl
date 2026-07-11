# ffi.jl — COM constants, types, FFI shims, vtable wrappers
# Native Julia ccall bindings to ole32/oleaut32 for IDispatch dynamic dispatch.
# Windows x64 only. stdcall is accepted and ignored on x64, required on x86.

# ---------------------------------------------------------------------------
# HRESULT aliases
# ---------------------------------------------------------------------------
const HRESULT = Clong
const S_OK = Clong(0)
const S_FALSE = Clong(1)
const RPC_E_CHANGED_MODE = reinterpret(Clong, UInt32(0x80010106))

# ---------------------------------------------------------------------------
# CLSCTX
# ---------------------------------------------------------------------------
const CLSCTX_INPROC_SERVER = UInt32(0x1)
const CLSCTX_INPROC_HANDLER = UInt32(0x2)
const CLSCTX_LOCAL_SERVER = UInt32(0x4)
const CLSCTX_REMOTE_SERVER = UInt32(0x10)
const CLSCTX_SERVER = CLSCTX_INPROC_SERVER | CLSCTX_LOCAL_SERVER | CLSCTX_REMOTE_SERVER
const CLSCTX_ALL = CLSCTX_SERVER | CLSCTX_INPROC_HANDLER

# ---------------------------------------------------------------------------
# DISPID
# ---------------------------------------------------------------------------
const DISPID_VALUE = Int32(0)
const DISPID_NEWENUM = Int32(-4)
const DISPID_UNKNOWN = Int32(-1)
const DISPID_PROPERTYPUT = Int32(-3)

# ---------------------------------------------------------------------------
# DISPATCH flags
# ---------------------------------------------------------------------------
const DISPATCH_METHOD = UInt16(0x1)
const DISPATCH_PROPERTYGET = UInt16(0x2)
const DISPATCH_PROPERTYPUT = UInt16(0x4)
const DISPATCH_PROPERTYPUTREF = UInt16(0x8)

# ---------------------------------------------------------------------------
# INVOKE flags (for reference; dynamic path uses DISPATCH_*)
# ---------------------------------------------------------------------------
const INVOKE_FUNC = UInt16(1)
const INVOKE_PROPERTYGET = UInt16(2)
const INVOKE_PROPERTYPUT = UInt16(4)
const INVOKE_PROPERTYPUTREF = UInt16(8)

# ---------------------------------------------------------------------------
# LCID
# ---------------------------------------------------------------------------
const LOCALE_USER_DEFAULT = UInt32(0x0400)
const DISPATCH_LCID = UInt32(0)

# ---------------------------------------------------------------------------
# COINIT
# ---------------------------------------------------------------------------
const COINIT_APARTMENTTHREADED = UInt32(0x2)
const COINIT_MULTITHREADED = UInt32(0x0)

# ---------------------------------------------------------------------------
# VARTYPE constants
# ---------------------------------------------------------------------------
const VT_EMPTY = UInt16(0x0)
const VT_NULL = UInt16(0x1)
const VT_I2 = UInt16(0x2)
const VT_I4 = UInt16(0x3)
const VT_R4 = UInt16(0x4)
const VT_R8 = UInt16(0x5)
const VT_CY = UInt16(0x6)
const VT_DATE = UInt16(0x7)
const VT_BSTR = UInt16(0x8)
const VT_DISPATCH = UInt16(0x9)
const VT_ERROR = UInt16(0xA)
const VT_BOOL = UInt16(0xB)
const VT_VARIANT = UInt16(0xC)
const VT_UNKNOWN = UInt16(0xD)
const VT_DECIMAL = UInt16(0xE)
const VT_I1 = UInt16(0x10)
const VT_UI1 = UInt16(0x11)
const VT_UI2 = UInt16(0x12)
const VT_UI4 = UInt16(0x13)
const VT_I8 = UInt16(0x14)
const VT_UI8 = UInt16(0x15)
const VT_INT = UInt16(0x16)
const VT_UINT = UInt16(0x17)
const VT_RECORD = UInt16(0x24)
const VT_ARRAY = UInt16(0x2000)
const VT_BYREF = UInt16(0x4000)

const DISP_E_PARAMNOTFOUND = reinterpret(Int32, UInt32(0x80020004))

# ---------------------------------------------------------------------------
# Core structs (x64 layout)
# ---------------------------------------------------------------------------
const WCHAR = Cwchar_t

struct GUID
    Data1::UInt32
    Data2::UInt16
    Data3::UInt16
    Data4::NTuple{8, UInt8}
end
const IID = GUID
const CLSID = GUID

# Zero GUID (IID_NULL)
const IID_NULL = GUID(0, 0, 0, (0, 0, 0, 0, 0, 0, 0, 0))

# VARIANT — 24 bytes on x64: 8 bytes header (vt + 3 reserved) + 16-byte value union
struct VARIANT
    vt::UInt16
    wReserved1::UInt16
    wReserved2::UInt16
    wReserved3::UInt16
    val::NTuple{2, UInt64}   # 16-byte value union; scalar at val[1] (offset 8)
end

# DISPPARAMS
struct DISPPARAMS
    rgvarg::Ptr{VARIANT}          # args in REVERSE order
    rgdispidNamedArgs::Ptr{Int32} # DISPID_PROPERTYPUT for put
    cArgs::UInt32
    cNamedArgs::UInt32
end

# EXCEPINFO
struct EXCEPINFO
    wCode::UInt16
    wReserved::UInt16
    bstrSource::Ptr{Cvoid}        # BSTR
    bstrDescription::Ptr{Cvoid}   # BSTR
    bstrHelpFile::Ptr{Cvoid}      # BSTR
    dwHelpContext::UInt32
    pvReserved::Ptr{Cvoid}
    pfnDeferredFillIn::Ptr{Cvoid}
    scode::Clong
end

# ---------------------------------------------------------------------------
# Vtable structs (IUnknown + IDispatch + IEnumVARIANT)
# ---------------------------------------------------------------------------
struct IUnknownVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
end
struct IUnknown
    lpVtbl::Ptr{IUnknownVtbl}
end

struct IDispatchVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
    GetTypeInfoCount::Ptr{Cvoid}
    GetTypeInfo::Ptr{Cvoid}
    GetIDsOfNames::Ptr{Cvoid}
    Invoke::Ptr{Cvoid}
end
struct IDispatch
    lpVtbl::Ptr{IDispatchVtbl}
end

struct IEnumVARIANTVtbl
    QueryInterface::Ptr{Cvoid}
    AddRef::Ptr{Cvoid}
    Release::Ptr{Cvoid}
    Next::Ptr{Cvoid}
    Skip::Ptr{Cvoid}
    Reset::Ptr{Cvoid}
    Clone::Ptr{Cvoid}
end
struct IEnumVARIANT
    lpVtbl::Ptr{IEnumVARIANTVtbl}
end

# ---------------------------------------------------------------------------
# IID constants (canonical byte values)
# ---------------------------------------------------------------------------
const IID_IDispatch = GUID(
    0x00020400, 0x0000, 0x0000, (0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)
)
const IID_IUnknown = GUID(
    0x00000000, 0x0000, 0x0000, (0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)
)
const IID_IEnumVARIANT = GUID(
    0x00020404, 0x0000, 0x0000, (0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)
)
const IID_IMoniker = GUID(
    0x0000000f, 0x0000, 0x0000, (0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46)
)

# ---------------------------------------------------------------------------
# COMException
# ---------------------------------------------------------------------------
struct COMException <: Exception
    hresult::Clong
    description::String
    source::String
end
COMException(hr::Clong, desc::AbstractString="") = COMException(hr, String(desc), "")

function Base.showerror(io::IO, e::COMException)
    print(io, "COMException(0x$(uppercase(string(unsigned(e.hresult), base=16, pad=8))))")
    if !isempty(e.description)
        print(io, ": ", e.description)
    end
    if !isempty(e.source)
        print(io, " [", e.source, "]")
    end
end

# check(hr, ctx) — throw COMException on failure
function check(hr::Clong, ctx::AbstractString)
    if hr < 0
        throw(COMException(hr, String(ctx)))
    end
    return hr
end

# ---------------------------------------------------------------------------
# Free-function ccall shims (ole32 / oleaut32)
# ---------------------------------------------------------------------------
function CoInitializeEx(pv, coInit)
    return ccall(
        (:CoInitializeEx, "ole32"), stdcall, HRESULT, (Ptr{Cvoid}, UInt32), pv, coInit
    )
end
CoUninitialize() = ccall((:CoUninitialize, "ole32"), stdcall, Cvoid, ())

function CLSIDFromProgID(progid, pclsid)
    return ccall(
        (:CLSIDFromProgID, "ole32"),
        stdcall,
        HRESULT,
        (Ptr{WCHAR}, Ptr{CLSID}),
        progid,
        pclsid,
    )
end
function CLSIDFromString(str, pclsid)
    return ccall(
        (:CLSIDFromString, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{WCHAR}, Ptr{CLSID}),
        str,
        pclsid,
    )
end
function IIDFromString(str, piid)
    return ccall(
        (:IIDFromString, "oleaut32"), stdcall, HRESULT, (Ptr{WCHAR}, Ptr{IID}), str, piid
    )
end

function CoCreateInstance(clsid, outer, ctx, iid, ppv)
    return ccall(
        (:CoCreateInstance, "ole32"),
        stdcall,
        HRESULT,
        (Ptr{CLSID}, Ptr{Cvoid}, UInt32, Ptr{IID}, Ptr{Ptr{Cvoid}}),
        clsid,
        outer,
        ctx,
        iid,
        ppv,
    )
end

function CreateBindCtx(res, ppbc)
    return ccall(
        (:CreateBindCtx, "ole32"), stdcall, HRESULT, (UInt32, Ptr{Ptr{Cvoid}}), res, ppbc
    )
end
function MkParseDisplayName(pbc, name, eaten, ppmk)
    return ccall(
        (:MkParseDisplayName, "ole32"),
        stdcall,
        HRESULT,
        (Ptr{Cvoid}, Ptr{WCHAR}, Ptr{UInt32}, Ptr{Ptr{Cvoid}}),
        pbc,
        name,
        eaten,
        ppmk,
    )
end

function GetActiveObject(clsid, reserved, ppunk)
    return ccall(
        (:GetActiveObject, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{CLSID}, Ptr{Cvoid}, Ptr{Ptr{Cvoid}}),
        clsid,
        reserved,
        ppunk,
    )
end

function SysAllocString(s)
    return ccall((:SysAllocString, "oleaut32"), stdcall, Ptr{Cvoid}, (Ptr{WCHAR},), s)
end
function SysAllocStringLen(s, n)
    return ccall(
        (:SysAllocStringLen, "oleaut32"), stdcall, Ptr{Cvoid}, (Ptr{WCHAR}, UInt32), s, n
    )
end
SysFreeString(b) = ccall((:SysFreeString, "oleaut32"), stdcall, Cvoid, (Ptr{Cvoid},), b)
SysStringLen(b) = ccall((:SysStringLen, "oleaut32"), stdcall, UInt32, (Ptr{Cvoid},), b)

VariantInit(pv) = ccall((:VariantInit, "oleaut32"), stdcall, Cvoid, (Ptr{VARIANT},), pv)
VariantClear(pv) = ccall((:VariantClear, "oleaut32"), stdcall, HRESULT, (Ptr{VARIANT},), pv)
function VariantChangeType(pvDst, pvSrc, flags, vt)
    return ccall(
        (:VariantChangeType, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{VARIANT}, Ptr{VARIANT}, UInt16, UInt16),
        pvDst,
        pvSrc,
        flags,
        vt,
    )
end

# SAFEARRAY
function SafeArrayGetDim(psa)
    return ccall((:SafeArrayGetDim, "oleaut32"), stdcall, UInt32, (Ptr{Cvoid},), psa)
end
function SafeArrayGetElemsize(psa)
    return ccall((:SafeArrayGetElemsize, "oleaut32"), stdcall, UInt32, (Ptr{Cvoid},), psa)
end
function SafeArrayGetLBound(psa, dim, bound)
    return ccall(
        (:SafeArrayGetLBound, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{Cvoid}, UInt32, Ptr{Int32}),
        psa,
        dim,
        bound,
    )
end
function SafeArrayGetUBound(psa, dim, bound)
    return ccall(
        (:SafeArrayGetUBound, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{Cvoid}, UInt32, Ptr{Int32}),
        psa,
        dim,
        bound,
    )
end
function SafeArrayGetElement(psa, idx, pv)
    return ccall(
        (:SafeArrayGetElement, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{Cvoid}, Ptr{Int32}, Ptr{Cvoid}),
        psa,
        idx,
        pv,
    )
end
function SafeArrayDestroy(psa)
    return ccall((:SafeArrayDestroy, "oleaut32"), stdcall, HRESULT, (Ptr{Cvoid},), psa)
end
function SafeArrayCreateVector(vt, lbound, count)
    return ccall(
        (:SafeArrayCreateVector, "oleaut32"),
        stdcall,
        Ptr{Cvoid},
        (UInt16, Int32, UInt32),
        vt,
        lbound,
        count,
    )
end
function SafeArrayPutElement(psa, idx, pv)
    return ccall(
        (:SafeArrayPutElement, "oleaut32"),
        stdcall,
        HRESULT,
        (Ptr{Cvoid}, Ptr{Int32}, Ptr{Cvoid}),
        psa,
        idx,
        pv,
    )
end

# ---------------------------------------------------------------------------
# Vtable method wrappers — IDispatch
# p is typed (needed for unsafe_load(p).lpVtbl); other params untyped for Ref/Ptr compat.
# ---------------------------------------------------------------------------
function QueryInterface(p::Ptr{IDispatch}, iid, ppv)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).QueryInterface,
        stdcall,
        HRESULT,
        (Ptr{IDispatch}, Ptr{IID}, Ptr{Ptr{Cvoid}}),
        p,
        iid,
        ppv,
    )
end
function AddRef(p::Ptr{IDispatch})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).AddRef, stdcall, Clong, (Ptr{IDispatch},), p
    )
end
function Release(p::Ptr{IDispatch})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Release, stdcall, Clong, (Ptr{IDispatch},), p
    )
end
function GetIDsOfNames(p::Ptr{IDispatch}, names, cNames, lcid, rgDispId)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).GetIDsOfNames,
        stdcall,
        HRESULT,
        (Ptr{IDispatch}, Ptr{IID}, Ptr{Ptr{WCHAR}}, UInt32, UInt32, Ptr{Int32}),
        p,
        Ref(IID_NULL),
        names,
        cNames,
        lcid,
        rgDispId,
    )
end
function Invoke(
    p::Ptr{IDispatch}, dispid, wFlags, pDispParams, pVarResult, pExcepInfo, puArgErr
)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Invoke,
        stdcall,
        HRESULT,
        (
            Ptr{IDispatch},
            Int32,
            Ptr{IID},
            UInt32,
            UInt16,
            Ptr{DISPPARAMS},
            Ptr{VARIANT},
            Ptr{EXCEPINFO},
            Ptr{UInt32},
        ),
        p,
        dispid,
        Ref(IID_NULL),
        DISPATCH_LCID,
        wFlags,
        pDispParams,
        pVarResult,
        pExcepInfo,
        puArgErr,
    )
end

# ---------------------------------------------------------------------------
# Vtable method wrappers — IUnknown (generic, for QueryInterface on raw unknowns)
# ---------------------------------------------------------------------------
function QueryInterface(p::Ptr{IUnknown}, iid, ppv)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).QueryInterface,
        stdcall,
        HRESULT,
        (Ptr{IUnknown}, Ptr{IID}, Ptr{Ptr{Cvoid}}),
        p,
        iid,
        ppv,
    )
end
function AddRef(p::Ptr{IUnknown})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).AddRef, stdcall, Clong, (Ptr{IUnknown},), p
    )
end
function Release(p::Ptr{IUnknown})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Release, stdcall, Clong, (Ptr{IUnknown},), p
    )
end

# ---------------------------------------------------------------------------
# Vtable method wrappers — IEnumVARIANT
# ---------------------------------------------------------------------------
function Next(p::Ptr{IEnumVARIANT}, celt, rgelt, pceltFetched)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Next,
        stdcall,
        HRESULT,
        (Ptr{IEnumVARIANT}, UInt32, Ptr{VARIANT}, Ptr{UInt32}),
        p,
        celt,
        rgelt,
        pceltFetched,
    )
end
function Skip(p::Ptr{IEnumVARIANT}, celt)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Skip,
        stdcall,
        HRESULT,
        (Ptr{IEnumVARIANT}, UInt32),
        p,
        celt,
    )
end
function ResetEnum(p::Ptr{IEnumVARIANT})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Reset, stdcall, HRESULT, (Ptr{IEnumVARIANT},), p
    )
end
function CloneEnum(p::Ptr{IEnumVARIANT}, ppenum)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Clone,
        stdcall,
        HRESULT,
        (Ptr{IEnumVARIANT}, Ptr{Ptr{IEnumVARIANT}}),
        p,
        ppenum,
    )
end

# QI on IEnumVARIANT (inherit IUnknown methods)
function AddRef(p::Ptr{IEnumVARIANT})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).AddRef, stdcall, Clong, (Ptr{IEnumVARIANT},), p
    )
end
function Release(p::Ptr{IEnumVARIANT})
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).Release, stdcall, Clong, (Ptr{IEnumVARIANT},), p
    )
end
function QueryInterface(p::Ptr{IEnumVARIANT}, iid, ppv)
    return ccall(
        unsafe_load(unsafe_load(p).lpVtbl).QueryInterface,
        stdcall,
        HRESULT,
        (Ptr{IEnumVARIANT}, Ptr{IID}, Ptr{Ptr{Cvoid}}),
        p,
        iid,
        ppv,
    )
end

# ---------------------------------------------------------------------------
# IMoniker BindToObject — read vtable pointer at offset 0, slot 4 (0-based)
# IMoniker vtable: QI=0, AddRef=1, Release=2, GetClassID=3, BindToObject=4
# ---------------------------------------------------------------------------
function BindToObject(p, pbc, pmkToLeft, riid, ppv)
    vtbl = unsafe_load(reinterpret(Ptr{Ptr{Cvoid}}, p))   # offset 0: lpVtbl
    fn = unsafe_load(reinterpret(Ptr{Cvoid}, vtbl + 4 * sizeof(Ptr{Cvoid})))  # slot 4
    return ccall(
        fn,
        stdcall,
        HRESULT,
        (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{IID}, Ptr{Ptr{Cvoid}}),
        p,
        pbc,
        pmkToLeft,
        riid,
        ppv,
    )
end

# ---------------------------------------------------------------------------
# Helper: BSTR alloc from Julia string
# ---------------------------------------------------------------------------
function bstr_alloc(s::AbstractString)::Ptr{Cvoid}
    data = transcode(WCHAR, String(s))
    # add NUL terminator (SysAllocString expects a NUL-terminated WCHAR string)
    push!(data, 0)
    GC.@preserve data begin
        return SysAllocString(pointer(data))
    end
end

# Helper: read BSTR into Julia String (does NOT free the BSTR)
function bstr_to_string(p::Ptr{Cvoid})::String
    p == C_NULL && return ""
    n = SysStringLen(p)
    n == 0 && return ""
    wptr = reinterpret(Ptr{WCHAR}, p)
    buf = unsafe_wrap(Vector{WCHAR}, wptr, n)
    return transcode(String, buf)
end
