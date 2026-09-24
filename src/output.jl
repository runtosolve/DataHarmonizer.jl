# Turning the clustering answer into the concordance: availability arithmetic, unit
# checks, tag resolution, and the CSV outputs.

const QUALIFIED = ("implied", "inferred", "simulated")

"""
    Member

One paper's holding of a canonical variable.
"""
struct Member
    code_tag::String
    symbol::String
    unit::String
    availability::String     # direct | implied | inferred | simulated
    evidence::String
    table_tags::Vector{String}
    conversion::String       # "" when none, "× 25.4", or "check"
    note::String
end
is_direct(m::Member) = m.availability == "direct"

"""
    split_symbols(s) -> Vector{String}

`"D_in, depth_in"` → `["D_in", "depth_in"]`. A member may name the same quantity under
more than one column.
"""
split_symbols(s::AbstractString) = filter(!isempty, String.(strip.(split(String(s), r"[,/;]+"))))

"""
    CanonicalVariable

One harmonized row: the canonical name, unit and description, plus one [`Member`](@ref)
per paper that has it and the availability arithmetic over the whole set.
"""
struct CanonicalVariable
    name::String
    description::String
    canonical_unit::String
    si_equivalent::String
    quantity_kind::String
    role::String
    members::Dict{String,Member}    # code_tag => Member
    n_papers::Int
    n_present::Int
    n_direct::Int
    n_qualified::Int
    conversion_needed::Bool
end
availability_pct(v::CanonicalVariable) = v.n_papers == 0 ? 0.0 : 100 * v.n_present / v.n_papers

"""
    Concordance

The whole harmonized set: the papers, the canonical rows, the model's own notes and the
checks this module ran over the answer.
"""
struct Concordance
    set_title::String
    summary::String
    papers::Vector{Paper}
    inventories::Vector{Inventory}
    variables::Vector{CanonicalVariable}
    notes::Vector{String}
    checks::Vector{String}
    tag_labels::Dict{String,String}   # table tag => the label the paper printed
    out::String
end

"""
    chip_label(c, tag, paper) -> String

The short form shown on a tag chip: the paper's own printed table number where there is
one (`"Table 3.3"` → `"T3.3"`), so a chip matches what a reader sees in the report.
"""
function chip_label(c::Concordance, tag::AbstractString, paper::AbstractString)
    lbl = get(c.tag_labels, String(tag), "")
    m = match(r"[Tt]able\s+([A-Za-z0-9\.\-]+)", lbl)
    m === nothing || return "T" * String(m[1])
    return short_tag(tag, paper)
end

function Base.show(io::IO, c::Concordance)
    shared = count(v -> v.n_present == v.n_papers, c.variables)
    println(io, "Concordance(\"", c.set_title, "\", ", length(c.papers), " papers, ",
            length(c.variables), " canonical variables, ", shared, " in every paper)")
    print(io, "  out: ", c.out)
end

# Paper citation: prefer the one printed in the CSV headers over the model's reading of it.
function citation_of(c::Concordance, code)
    i = findfirst(p -> p.code_tag == code, c.papers)
    i === nothing || isempty(c.papers[i].citation) || return c.papers[i].citation
    return citation_of(c.inventories, code)
end
citation_of(invs::Vector{Inventory}, code) = begin
    i = findfirst(v -> code_tag(v) == code, invs)
    i === nothing ? "" : String(get(invs[i].data, "citation", ""))
end
title_of(invs, code) = begin
    i = findfirst(v -> code_tag(v) == code, invs)
    i === nothing ? "" : String(get(invs[i].data, "title", ""))
end
experiment_of(invs, code) = begin
    i = findfirst(v -> code_tag(v) == code, invs)
    i === nothing ? "" : String(get(invs[i].data, "experiment", ""))
end

const ROLE_ORDER = Dict("measured_output" => 1, "material_property" => 2, "specimen_parameter" => 3,
                        "derived_ratio" => 4, "predicted_value" => 5, "test_condition" => 6, "identifier" => 7)
const ROLE_LABEL = Dict("measured_output" => "Measured output", "material_property" => "Material property",
                        "specimen_parameter" => "Specimen parameter", "derived_ratio" => "Derived ratio",
                        "predicted_value" => "Predicted value", "test_condition" => "Test condition",
                        "identifier" => "Identifier")
role_label(r) = get(ROLE_LABEL, r, replace(String(r), "_" => " "))

"""
    build_concordance(parsed, invs, papers, out) -> Concordance

Assemble the clustering answer into a [`Concordance`](@ref), computing availability,
checking the units and resolving every table tag against the tables actually on disk.
"""
function build_concordance(parsed::AbstractDict, invs::Vector{Inventory}, papers::Vector{Paper}, out::AbstractString)
    codes = [p.code_tag for p in papers]
    known_tags = Set(t.tag for p in papers for t in p.tables)
    checks = String[]
    vars = CanonicalVariable[]

    for cv in get(parsed, "canonical_variables", Any[])
        name = String(get(cv, "name", "?"))
        cunit = String(get(cv, "canonical_unit", ""))
        members = Dict{String,Member}()
        for m in get(cv, "members", Any[])
            code = String(get(m, "code_tag", ""))
            if !(code in codes)
                push!(checks, "row \"$name\": member names an unknown paper \"$code\"; dropped")
                continue
            end
            tags = String[]
            for t in get(m, "table_tags", Any[])
                ts = String(t)
                if ts in known_tags
                    push!(tags, ts)
                else
                    # tolerate a tag given without its paper prefix
                    alt = string(code, "_", ts)
                    if alt in known_tags
                        push!(tags, alt)
                    else
                        push!(checks, "row \"$name\" ($code): table tag \"$ts\" is not among the extracted tables")
                        push!(tags, ts)
                    end
                end
            end
            munit = String(get(m, "unit", ""))
            conv = conversion_note(munit, cunit)
            conv == "check" && push!(checks, "row \"$name\" ($code): cannot convert \"$munit\" to \"$cunit\"; check the unit")
            avail = String(get(m, "availability", "direct"))
            avail in AVAILABILITY || (push!(checks, "row \"$name\" ($code): unknown availability \"$avail\"; treated as direct"); avail = "direct")
            haskey(members, code) && push!(checks, "row \"$name\": paper $code listed twice; kept the first")
            get!(members, code, Member(code, String(get(m, "symbol", "")), munit, avail,
                                       String(get(m, "evidence", "")), tags, conv, String(get(m, "note", ""))))
        end
        n_direct = count(is_direct, values(members))
        n_present = length(members)
        push!(vars, CanonicalVariable(name, String(get(cv, "description", "")), cunit, si_equivalent(cunit),
                                      String(get(cv, "quantity_kind", "")), String(get(cv, "role", "")),
                                      members, length(codes), n_present, n_direct, n_present - n_direct,
                                      get(cv, "conversion_needed", false) === true ||
                                      any(m -> !isempty(m.conversion), values(members))))
    end

    isempty(vars) && push!(checks, "the clustering pass returned no canonical variables")
    # every inventoried variable should land somewhere; report the ones that did not.
    # a member may carry several names for the same quantity ("D_in, depth_in"), so split.
    placed = Set{Tuple{String,String}}()
    for v in vars, m in values(v.members), s in split_symbols(m.symbol)
        push!(placed, (m.code_tag, s))
    end
    for inv in invs
        for v in variables(inv)
            syms = String.(get(v, "symbols", Any[]))
            isempty(syms) && continue
            any(s -> (code_tag(inv), s) in placed, syms) && continue
            push!(checks, "$(code_tag(inv)): inventoried variable \"$(first(syms))\" did not reach any canonical row")
        end
    end

    sort!(vars; by=v -> (get(ROLE_ORDER, v.role, 9), -v.n_present, -v.n_direct, lowercase(v.name)))
    labels = Dict{String,String}(t.tag => t.table_label for p in papers for t in p.tables)
    return Concordance(String(get(parsed, "set_title", "Harmonized variables")),
                       String(get(parsed, "summary", "")), papers, invs, vars,
                       String.(get(parsed, "notes", Any[])), checks, labels, out)
end

# ---- CSV outputs ---------------------------------------------------------------------------------

mark_of(m::Union{Nothing,Member}) = m === nothing ? "" :
    (m.availability == "direct" ? "Yes" : string("Yes (", uppercasefirst(m.availability), ")"))

"""
    write_common_variables(c::Concordance) -> String

`common_variables.csv`: one row per canonical variable, one column per paper, in the
"Summary Table of Common Measured Variables" shape.
"""
function write_common_variables(c::Concordance)
    codes = [p.code_tag for p in c.papers]
    path = joinpath(c.out, "common_variables.csv")
    header = vcat(["common_variable", "description", "canonical_unit", "si_equivalent", "quantity_kind",
                   "role", "n_present", "n_papers", "availability_pct", "n_direct", "n_qualified",
                   "conversion_needed"], codes, [string(cd, "_symbol") for cd in codes], [string(cd, "_tables") for cd in codes])
    open(path, "w") do io
        println(io, "# Harmonized set: ", c.set_title)
        println(io, "# Papers: ", join(codes, ", "))
        println(io, "# Marks: Yes = reported as its own column; Yes (Implied) = stated in a note, not a column;")
        println(io, "#        Yes (Inferred) = needs outside context or a figure; Yes (Simulated) = from a model or code equation;")
        println(io, "#        empty = not addressed in that paper.")
        println(io, "# availability_pct counts every paper where the variable can be obtained at all;")
        println(io, "#        n_direct is how many of those report it as a column.")
        println(io, "# Generated by DataHarmonizer on ", Dates.format(today(), "yyyy-mm-dd"))
        println(io, csv_line(header))
        for v in c.variables
            row = [v.name, v.description, v.canonical_unit, v.si_equivalent, v.quantity_kind, role_label(v.role),
                   string(v.n_present), string(v.n_papers), string(round(availability_pct(v); digits=1)),
                   string(v.n_direct), string(v.n_qualified), v.conversion_needed ? "yes" : "no"]
            for cd in codes
                push!(row, mark_of(get(v.members, cd, nothing)))
            end
            for cd in codes
                m = get(v.members, cd, nothing)
                push!(row, m === nothing ? "" : (isempty(m.conversion) ? m.symbol : string(m.symbol, " [", m.unit, " ", m.conversion, "]")))
            end
            for cd in codes
                m = get(v.members, cd, nothing)
                push!(row, m === nothing ? "" : join(m.table_tags, "; "))
            end
            println(io, csv_line(row))
        end
    end
    return path
end

"""
    write_variable_inventory(c::Concordance) -> String

`variable_inventory.csv`: the long form, one row per paper per variable, for filtering
and joining.
"""
function write_variable_inventory(c::Concordance)
    path = joinpath(c.out, "variable_inventory.csv")
    header = ["common_variable", "role", "canonical_unit", "paper", "citation", "symbol", "reported_unit",
              "conversion_to_canonical", "availability", "evidence", "table_tags", "note"]
    open(path, "w") do io
        println(io, "# Long form of the harmonized set: one row per paper per variable.")
        println(io, "# Generated by DataHarmonizer on ", Dates.format(today(), "yyyy-mm-dd"))
        println(io, csv_line(header))
        for v in c.variables, cd in [p.code_tag for p in c.papers]
            m = get(v.members, cd, nothing)
            m === nothing && continue
            println(io, csv_line([v.name, role_label(v.role), v.canonical_unit, cd, citation_of(c, cd),
                                  m.symbol, m.unit, m.conversion, m.availability, m.evidence,
                                  join(m.table_tags, "; "), m.note]))
        end
    end
    return path
end

"""
    write_source_tables(c::Concordance) -> String

`source_tables.csv`: every extracted table that took part, so a tag in the concordance
resolves to a file on disk.
"""
function write_source_tables(c::Concordance)
    path = joinpath(c.out, "source_tables.csv")
    header = ["paper", "table_tag", "table_label", "pages", "n_rows", "n_columns", "file", "content"]
    open(path, "w") do io
        println(io, "# Every extracted table read by DataHarmonizer, so a table tag resolves to a file.")
        println(io, csv_line(header))
        for p in c.papers, t in p.tables
            println(io, csv_line([p.code_tag, t.tag, t.table_label, t.pages, string(length(t.rows)),
                                  string(length(t.columns)), t.name, t.content]))
        end
    end
    return path
end
