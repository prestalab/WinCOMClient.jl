# test/runtests.jl — smoke test for WinCOMClient.jl
# Uses only the Test stdlib. Two paths:
# 1. Excel (if installed) — full end-to-end automation
# 2. Scripting.FileSystemObject (always on Windows) — dynamic dispatch surface

using Aqua
using WinCOMClient
using Test

    @testset "WinCOMClient.jl" begin
    @testset "Package quality" begin
        Aqua.test_all(WinCOMClient)
    end
    @testset "VARIANT scalar conversions" begin
        for x in (
            true,
            Int8(-7),
            Int16(-300),
            Int32(-40_000),
            Int64(-5),
            UInt8(7),
            UInt16(300),
            UInt32(40_000),
            UInt64(5),
            Float32(1.25),
            Float64(-2.5),
            nothing,
            missing,
        )
            variant = Ref{WinCOMClient.VARIANT}()
            WinCOMClient.to_variant(x, variant)
            @test isequal(WinCOMClient.from_variant(variant[]), x)
            WinCOMClient.VariantClear(variant)
        end
    end

    # ---- Fallback: Scripting.FileSystemObject (always on Windows) ----
    @testset "FileSystemObject" begin
        fso = Dispatch("Scripting.FileSystemObject")
        @test fso isa Dispatch

        # method with arg -> Bool
        @test fso.DriveExists("C:") == true

        # method with arg -> Dispatch (sub-object)
        d = fso.GetDrive("C:")
        @test d isa Dispatch

        # property read () -> Int
        @test d.TotalSize() > 0

        # collection property read ()
        drives = fso.Drives()
        @test drives isa Dispatch

        # Count-based length
        @test length(drives) >= 1

        # IEnumVARIANT iteration
        n = 0
        for drv in drives
            n += 1
        end
        @test n >= 1
    end

    # ---- Primary: Excel (if installed) ----
    @testset "Excel" begin
        xl = nothing
        try
            xl = Dispatch("Excel.Application")
        catch e
            @test_skip "Excel not installed ($(e isa COMException ? e.description : e))"
        end

        if xl !== nothing
            try
                xl.Visible = false
                ver = xl.Version()
                @test ver isa String && !isempty(ver)

                wb = xl.Workbooks()
                newwb = wb.Add()
                ws = newwb.Worksheets(1)
                c = ws.Range("A1")
                c.Value = "hi"
                @test c.Value() == "hi"
                newwb.Close(false)
            finally
                xl.Quit()
            end
        end
    end
end
