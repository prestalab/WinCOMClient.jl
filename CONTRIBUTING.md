# Contributing

Contributions are welcome. COMClient.jl is intentionally focused on native Windows COM Automation through `IDispatch`; callbacks and remote DCOM are outside the current scope.

## Development

Use Julia 1.10 or later on Windows x64:

```julia
using Pkg
Pkg.activate(".")
Pkg.test()
```

Format changed Julia files with JuliaFormatter and keep new behavior covered by tests. Tests must not require Microsoft Office; Office-specific tests should remain optional.

Before opening a merge request, run the complete test suite and describe the Windows and Julia versions used. Do not include generated manifests, coverage files, or editor settings.
