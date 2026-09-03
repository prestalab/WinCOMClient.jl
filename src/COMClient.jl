# WinCOMClient.jl — Native Julia COM client (dynamic dispatch)
#
# Port of pywin32 win32com.client dynamic dispatch path to Julia via ccall
# to ole32/oleaut32. No Python dependency. Windows x64 only.
#
# API compatibility with PythonCall.jl: the Dispatch object mirrors PythonCall.jl's
# Py object semantics — Base.getproperty/setproperty!/getindex/setindex!/length/
# iterate/callable/show — so usage is familiar.
#
# Lazy COMMember model (PythonCall.jl convention):
#   obj.X        -> returns a COMMember (lazy, not yet invoked)
#   obj.X()      -> invokes with zero args (property read / no-arg method)
#   obj.X(args)  -> invokes with args (method call)
#   obj.X = v    -> property put
#
# This means bare property reads need a trailing (), matching PythonCall.jl's
# obj.X() convention. This is the one deviation from Python win32com.client
# (where bare obj.X reads); it's the unavoidable consequence of Julia lacking
# Python's __getattr__+__call__ duality.

module WinCOMClient

using Dates

include("ffi.jl")
include("dispatch.jl")
include("variant.jl")

# ---------------------------------------------------------------------------
# COM initialization
# ---------------------------------------------------------------------------
const _com_inited = Ref{Bool}(false)

@inline function _require_windows()
    Sys.iswindows() || error("WinCOMClient.jl supports Windows only")
    Sys.WORD_SIZE == 64 || error("WinCOMClient.jl supports 64-bit Windows only")
    return nothing
end

function __init__()
    Sys.iswindows() || return nothing
    _require_windows()
    if !_com_inited[]
        hr = CoInitializeEx(C_NULL, COINIT_MULTITHREADED)
        if hr == S_OK || hr == S_FALSE || hr == RPC_E_CHANGED_MODE
            _com_inited[] = true
        else
            # Unexpected error — surface it
            error(
                "CoInitializeEx failed: 0x$(uppercase(string(unsigned(hr), base=16, pad=8)))",
            )
        end
    end
    return nothing
end

"""
    CoInitialize()

Initialize COM for the current process if WinCOMClient has not initialized it already.
"""
function CoInitialize()
    _require_windows()
    if !_com_inited[]
        __init__()
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Top-level functions (port of __init__.py)
# ---------------------------------------------------------------------------

"""
    Dispatch(source, [name]; clsctx=WinCOMClient.CLSCTX_SERVER)

Create or attach to a COM Automation object and return an owned dynamic `Dispatch`
wrapper. `source` may be a ProgID string, CLSID, existing wrapper, or `IDispatch`
pointer. Call `close` when deterministic release is required.
"""
function Dispatch(
    x, name::Union{Nothing, AbstractString}=nothing; clsctx::UInt32=CLSCTX_SERVER
)
    _require_windows()
    if x isa Dispatch
        return x
    elseif x isa AbstractString
        nm = name === nothing ? String(x) : String(name)
        # Try GetActiveObject first (running instance), fall back to CoCreateInstance
        p = get_active_idispatch(x)
        if p == C_NULL
            p = create_instance(progid_to_clsid(x), clsctx)
        end
        return wrap_dispatch(p, nm)
    elseif x isa GUID
        nm = name === nothing ? string(x) : String(name)
        p = create_instance(x, clsctx)
        return wrap_dispatch(p, nm)
    elseif x isa Ptr{IDispatch}
        nm = name === nothing ? "<unknown>" : String(name)
        return wrap_dispatch(x, nm)
    else
        error("Dispatch: unsupported argument type $(typeof(x))")
    end
end

"""
    DispatchEx(clsid, [machine]; clsctx=nothing, name=nothing)

Create a local COM object. Remote DCOM through `machine` is not supported.
"""
function DispatchEx(
    clsid,
    machine::Union{Nothing, AbstractString}=nothing;
    clsctx::Union{Nothing, UInt32}=nothing,
    name::Union{Nothing, AbstractString}=nothing,
)
    _require_windows()
    if machine !== nothing
        throw(
            ErrorException(
                "WinCOMClient: remote DCOM (machine=...) not supported in minimal scope"
            ),
        )
    end
    ctx = clsctx === nothing ? CLSCTX_SERVER : clsctx
    return Dispatch(clsid, name; clsctx=ctx)
end

# GetObject(pathname=nothing, class=nothing; clsctx=CLSCTX_ALL)
# Port of __init__.py:57-86
function GetObject(
    pathname::Union{Nothing, AbstractString}=nothing,
    class::Union{Nothing, AbstractString}=nothing;
    clsctx::UInt32=CLSCTX_ALL,
)
    _require_windows()
    if pathname === nothing && class === nothing
        throw(ArgumentError("GetObject: specify pathname or class"))
    end
    if pathname !== nothing && class !== nothing
        throw(ArgumentError("GetObject: specify pathname or class, not both"))
    end
    if class !== nothing
        return GetActiveObject(class; clsctx=clsctx)
    end
    # pathname set -> moniker
    return Moniker(pathname; clsctx=clsctx)
end

"""
    GetActiveObject(class; clsctx=WinCOMClient.CLSCTX_ALL)

Attach to a running COM object identified by ProgID or CLSID.
"""
function GetActiveObject(class; clsctx::UInt32=CLSCTX_ALL)
    _require_windows()
    cls = class isa AbstractString ? progid_to_clsid(class) : class
    p = get_active_idispatch(cls)
    if p == C_NULL
        error("GetActiveObject: no running instance of $class")
    end
    return wrap_dispatch(p, string(class))
end

"""
    Moniker(pathname; clsctx=WinCOMClient.CLSCTX_ALL)

Bind a COM display-name moniker and return its `IDispatch` wrapper.
"""
function Moniker(pathname::AbstractString; clsctx::UInt32=CLSCTX_ALL)
    _require_windows()
    p = moniker_bind(pathname)
    return wrap_dispatch(p, String(pathname))
end

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
export Dispatch, DispatchEx, GetObject, GetActiveObject, Moniker
export CoInitialize, COMException, COMMember, value, ptr

end # module WinCOMClient
