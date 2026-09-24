using Test
using JSON
using DataHarmonizer
const DH = DataHarmonizer

# Two fake papers written in the two header conventions the parser has to accept.
function make_fixture(dir)
    a = joinpath(dir, "11"); b = joinpath(dir, "230")
    mkpath(a); mkpath(b)
    # convention 1: SOURCE_ID / TABLE / TAG / COLUMNS block
    write(joinpath(a, "AAA_0101_table3-3_results.csv"), """
    # SOURCE_ID: AAA_0101
    # SOURCE_TITLE: A Study of Something (Doe & Roe, 2001, CES 01-1)
    # TABLE: Table 3.3 - Test Results (pp.37-39)
    # TAG: EOF_PRIMARY_RESULTS
    # EXPERIMENT_TYPE: Loaded to failure in a testing machine; per-web failure load
    #   Pt = specimen failure load / 4.
    # NOTE: 3 results across 2 specimens.
    # FLAG: one column preserved verbatim from the source.
    # COLUMNS:
    # specimen_id  - Specimen code
    # t_in         - Web thickness, inches
    # Pt_kips_per_web - MEASURED per-web failure load, kips
    specimen_id,t_in,Pt_kips_per_web
    8Z058,0.058,1.23
    8Z115,0.115,2.34
    8C058,0.058,1.11
    """)
    # convention 2: Source / Tag / Content / Units
    write(joinpath(b, "BBB_0202_Table7_TestData.csv"), """
    # Source: BBB_0202 | Roe, R. (2002), "Another Study of Something," Table VII, pp.43-44
    # Tag: BBB_0202_TABLE7_ZTESTDATA
    # Content: Measured test data for Z-section specimens under EOF loading
    # Units: t_in=inches, P_t_kips=kips (measured tested load per web)
    # N (bearing length) = 2.625 in for all specimens in this table
    specimen_id,t_in,P_t_kips
    Z1.1,0.061,1.036
    Z1.2,0.061,0.993
    """)
    # files that must be ignored
    write(joinpath(b, "BBB_0202_Extraction_Reference.docx"), "not a table")
    write(joinpath(b, "~\$BB_0202_Extraction_Reference.docx"), "lock")
    cp(joinpath(b, "BBB_0202_Table7_TestData.csv"), joinpath(b, "BBB_0202_Table7_TestData (1).csv"))
    return dir
end

@testset "DataHarmonizer" begin

@testset "units" begin
    @test DH.lookup_unit("kips").symbol == "kip"
    @test DH.lookup_unit("INCHES").symbol == "in"
    @test DH.lookup_unit("wibble") === nothing
    @test DH.conversion_factor("in", "mm") ≈ 25.4
    @test DH.conversion_factor("kip", "kN") ≈ 4.448222
    @test DH.conversion_factor("ksi", "MPa") ≈ 6.894757 atol = 1e-6
    @test DH.conversion_factor("in", "kip") === nothing        # different kinds
    @test DH.conversion_factor("in", "wibble") === nothing
    @test DH.si_equivalent("in") == "= 25.4 mm"
    @test DH.si_equivalent("kip") == "= 4.448 kN"
    @test DH.si_equivalent("mm") == ""                          # already SI
    @test DH.si_equivalent("") == ""
    @test DH.conversion_note("kips", "kip") == ""               # same unit, different spelling
    @test DH.conversion_note("mm", "in") == "× 0.03937"
    @test DH.conversion_note("in", "kip") == "check"
    @test DH.conversion_note("", "kip") == ""
end

mktempdir() do dir
    make_fixture(dir)
    papers = collect_papers(dir)

    @testset "tolerant header parsing" begin
        @test length(papers) == 2
        pa = papers[findfirst(p -> p.code_tag == "AAA_0101", papers)]
        pb = papers[findfirst(p -> p.code_tag == "BBB_0202", papers)]
        @test length(pa.tables) == 1 && length(pb.tables) == 1   # docx, lock and duplicate skipped
        ta, tb = pa.tables[1], pb.tables[1]

        # convention 1
        @test ta.tag == "AAA_0101_EOF_PRIMARY_RESULTS"           # prefixed with the paper code
        @test ta.table_label == "Table 3.3" && ta.pages == "37-39"
        @test startswith(ta.source_title, "A Study of Something")
        @test occursin("per-web failure load", ta.content)       # wrapped value joined
        @test occursin("Pt = specimen failure load / 4", ta.content)
        @test length(ta.coldefs) == 3
        @test ta.coldefs["Pt_kips_per_web"] == "MEASURED per-web failure load, kips"
        @test any(n -> occursin("3 results across 2 specimens", n), ta.notes)
        @test any(n -> occursin("preserved verbatim", n), ta.notes)
        @test ta.columns == ["specimen_id", "t_in", "Pt_kips_per_web"]
        @test length(ta.rows) == 3

        # convention 2
        @test tb.tag == "BBB_0202_TABLE7_ZTESTDATA"
        @test tb.table_label == "Table VII" && tb.pages == "43-44"
        @test tb.source_title == "Another Study of Something,"   # pulled from the quoted title
        @test occursin("Z-section specimens", tb.content)
        @test occursin("kips", tb.units)
        @test any(n -> occursin("bearing length", n), tb.notes)  # the implied-variable note survives
        @test length(tb.rows) == 2
    end

    @testset "paper digest" begin
        d = DH.paper_digest(papers[1]; sample_rows=2)
        @test occursin("PAPER CODE TAG: AAA_0101", d)
        @test occursin("<table tag=\"AAA_0101_EOF_PRIMARY_RESULTS\">", d)
        @test occursin("Pt_kips_per_web  — MEASURED per-web failure load", d)
        @test occursin("first 2 of 3 data rows", d)
        @test !occursin("8C058", d)                              # third row not sent
        @test cld(sizeof(d), 4) < 1500                           # stays compact
    end

    @testset "concordance assembly" begin
        invs = [DH.Inventory(p, Dict{String,Any}("code_tag" => p.code_tag,
                    "citation" => p.code_tag == "AAA_0101" ? "Doe, J. (2001)" : "Roe, R. (2002)",
                    "year" => "2001", "title" => "T", "experiment" => "E",
                    "variables" => Any[Dict{String,Any}("symbols" => Any[p.code_tag == "AAA_0101" ? "Pt_kips_per_web" : "P_t_kips"],
                        "name" => "load", "definition" => "d", "unit" => "kips", "quantity_kind" => "force",
                        "role" => "measured_output", "availability" => "direct", "evidence" => "Table",
                        "table_tags" => Any[p.tables[1].tag], "note" => "")])) for p in papers]
        parsed = Dict{String,Any}(
            "set_title" => "Web crippling", "summary" => "S", "notes" => Any["a judgement call"],
            "canonical_variables" => Any[
                Dict{String,Any}("name" => "Tested load per web", "description" => "d",
                    "canonical_unit" => "kip", "quantity_kind" => "force", "role" => "measured_output",
                    "conversion_needed" => false, "members" => Any[
                        Dict{String,Any}("code_tag" => "AAA_0101", "symbol" => "Pt_kips_per_web", "unit" => "kips",
                            "availability" => "direct", "evidence" => "Table 3.3",
                            "table_tags" => Any["AAA_0101_EOF_PRIMARY_RESULTS"], "note" => ""),
                        Dict{String,Any}("code_tag" => "BBB_0202", "symbol" => "P_t_kips", "unit" => "kips",
                            "availability" => "direct", "evidence" => "Table VII",
                            "table_tags" => Any["BBB_0202_TABLE7_ZTESTDATA"], "note" => "")]),
                Dict{String,Any}("name" => "Bearing length", "description" => "d2",
                    "canonical_unit" => "in", "quantity_kind" => "length", "role" => "test_condition",
                    "conversion_needed" => true, "members" => Any[
                        Dict{String,Any}("code_tag" => "BBB_0202", "symbol" => "N", "unit" => "mm",
                            "availability" => "implied", "evidence" => "header note",
                            "table_tags" => Any["BBB_0202_TABLE7_ZTESTDATA", "NOT_A_REAL_TAG"], "note" => ""),
                        Dict{String,Any}("code_tag" => "GHOST_9999", "symbol" => "x", "unit" => "in",
                            "availability" => "direct", "evidence" => "", "table_tags" => Any[], "note" => "")])])

        c = DH.build_concordance(parsed, invs, papers, dir)
        @test c.set_title == "Web crippling"
        @test length(c.variables) == 2
        # measured_output sorts ahead of test_condition
        @test c.variables[1].name == "Tested load per web"
        v1, v2 = c.variables
        @test v1.n_present == 2 && v1.n_direct == 2 && v1.n_qualified == 0
        @test DH.availability_pct(v1) == 100
        @test v1.si_equivalent == "= 4.448 kN"
        @test isempty(v1.members["AAA_0101"].conversion)          # kips → kip needs no conversion
        @test v2.n_present == 1 && v2.n_direct == 0 && v2.n_qualified == 1
        @test DH.availability_pct(v2) == 50
        @test v2.members["BBB_0202"].conversion == "× 0.03937"    # mm → in
        @test v2.conversion_needed
        @test !haskey(v2.members, "GHOST_9999")                   # unknown paper dropped
        @test any(s -> occursin("unknown paper", s), c.checks)
        @test any(s -> occursin("NOT_A_REAL_TAG", s), c.checks)
        @test c.notes == ["a judgement call"]

        @testset "CSV outputs" begin
            DH.write_common_variables(c); DH.write_variable_inventory(c); DH.write_source_tables(c)
            h, rows = DH.read_csv(joinpath(dir, "common_variables.csv"))
            @test h[1:3] == ["common_variable", "description", "canonical_unit"]
            @test "AAA_0101" in h && "BBB_0202_symbol" in h && "AAA_0101_tables" in h
            @test length(rows) == 2
            r1 = rows[1]
            @test r1[1] == "Tested load per web"
            @test r1[findfirst(==("AAA_0101"), h)] == "Yes"
            @test r1[findfirst(==("BBB_0202_symbol"), h)] == "P_t_kips"
            @test r1[findfirst(==("availability_pct"), h)] == "100.0"
            r2 = rows[2]
            @test r2[findfirst(==("AAA_0101"), h)] == ""          # absent paper leaves an empty mark
            @test r2[findfirst(==("BBB_0202"), h)] == "Yes (Implied)"
            @test occursin("× 0.03937", r2[findfirst(==("BBB_0202_symbol"), h)])
            h2, rows2 = DH.read_csv(joinpath(dir, "variable_inventory.csv"))
            @test length(rows2) == 3                              # 2 members + 1 member
            h3, rows3 = DH.read_csv(joinpath(dir, "source_tables.csv"))
            @test length(rows3) == 2
            @test rows3[1][2] == "AAA_0101_EOF_PRIMARY_RESULTS"
        end

        @testset "HTML page" begin
            html = render_concordance(c)
            @test startswith(html, "<!doctype html>") && endswith(strip(html), "</html>")
            for tag in ("html", "head>", "body", "table>", "thead", "tbody", "style", "section")
                @test count("<$tag", html) == count("</$(rstrip(tag, '>'))>", html)
            end
            @test occursin("--navy:", html) && occursin("var(--paper)", html)
            @test occursin("prefers-color-scheme: dark", html) && occursin("[data-theme=\"dark\"]", html)
            @test occursin("Tested load per web", html)
            @test occursin("AAA_0101_EOF_PRIMARY_RESULTS", html)  # full tag in the title attribute
            @test occursin("&times;", html)                       # the absent mark
            @test occursin("IMPLIED", uppercase(html))
            @test occursin("× 0.03937", html)
            @test occursin("Measured output", html) && occursin("Test condition", html)
            @test occursin("a judgement call", html)
            @test occursin("NOT_A_REAL_TAG", html)                # checks surfaced on the page
            @test !occursin("<script", html)
        end

        @testset "short tags" begin
            @test DH.short_tag("MBMA_9408_TABLE7_ZTESTDATA", "MBMA_9408") == "T7"
            @test DH.short_tag("MBMA_0204_EOF_PRIMARY_RESULTS", "MBMA_0204") == "EOF_PRIMARY_RESULT"
        end
    end
end

# ---- live test: opt-in, costs money -----------------------------------------------------------
live = get(ENV, "DATAHARMONIZER_LIVE", "0") == "1"
DH.load_dotenv!()
set_dir = normpath(joinpath(@__DIR__, "..", "..", "11,211,230 Flange"))
if live && !isempty(get(ENV, "ANTHROPIC_API_KEY", "")) && isdir(set_dir)
    @testset "live harmonization" begin
        c = harmonize_papers(set_dir)
        @test length(c.papers) == 3
        @test length(c.variables) > 5
        @test any(v -> v.n_present == v.n_papers, c.variables)    # something is shared
        @test isfile(joinpath(c.out, "concordance.html"))
        @test isfile(joinpath(c.out, "common_variables.csv"))
    end
else
    @info "Live harmonization test skipped (set DATAHARMONIZER_LIVE=1 and ANTHROPIC_API_KEY to run it)"
end

end # testset
