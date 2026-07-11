# COMClient.jl

A lightweight, native Windows COM Automation client for Julia. It calls `ole32` and `oleaut32` directly and does not depend on Python.

> **Status:** Early development. The package supports dynamic `IDispatch` clients but does not implement COM event callbacks.

## Requirements

- Windows x64
- Julia 1.10 or later
- A COM Automation server to control

## Installation

```julia
using Pkg
Pkg.add("COMClient")
```

Until the first registry release becomes available, install directly from GitHub:

```julia
Pkg.add(url="https://github.com/prestalab/COMClient.jl.git")
```

For local development:

```julia
using Pkg
Pkg.develop(path=raw"C:\projects\COMClient.jl")
```

## Usage

```julia
using COMClient

excel = Dispatch("Excel.Application")
try
    excel.Visible = true
    workbook = excel.Workbooks().Add()
    sheet = workbook.Worksheets(1)
    sheet.Range("A1").Value = "Hello from Julia"
finally
    excel.Quit()
    close(excel)
end
```

Members are resolved lazily. Call a property with no arguments to read it:

```julia
version = excel.Version()
```

Collections support indexing, `length`, and iteration when exposed by the COM server:

```julia
for drive in Dispatch("Scripting.FileSystemObject").Drives()
    println(drive.DriveLetter())
end
```

Use `close(object)` for deterministic release of an owned `IDispatch` reference. A finalizer provides fallback cleanup.

## API

- `Dispatch(progid_or_clsid)` creates or attaches to a COM object.
- `DispatchEx(clsid)` creates a local COM object; remote DCOM is not supported.
- `GetActiveObject(class)` attaches to a running object.
- `GetObject(pathname=...)` and `Moniker(path)` bind through a COM moniker.
- `value(member)` performs an explicit property read.
- `close(object)` releases the owned COM reference.

## Limitations

- Windows x64 only.
- COM callbacks and connection points are not implemented.
- Remote DCOM is not implemented.
- SAFEARRAY support is currently limited to one and two dimensions.
- COM initialization is process-oriented; applications needing strict apartment control should initialize COM before loading the package.

## Development

Run the test suite with:

```julia
using Pkg
Pkg.test()
```

The integration tests use `Scripting.FileSystemObject`; Excel tests run only when Excel is installed.

## License

COMClient.jl is available under the MIT License. See [`LICENSE`](LICENSE).
