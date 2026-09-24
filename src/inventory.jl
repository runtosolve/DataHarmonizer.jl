# Pass 1: one call per paper. Build a raw inventory of every quantity that paper reports,
# keeping the paper's own symbol exactly as printed.

const INVENTORY_SYSTEM = """
You are a structural-engineering data curator building an inventory of the quantities one
research paper reports, as the first step of harmonizing several papers together.

You are given every data table extracted from ONE paper: each table's tag, label, pages,
description, units line, header notes, its column names with any definitions, and a few
sample data rows.

List EVERY distinct quantity the paper reports. Rules:

- One entry per distinct physical quantity, not one per column. If the same quantity
  appears in several tables (a thickness in both a dimensions table and a results table),
  give ONE entry and list every table tag it appears in.
- `symbol` is the column name EXACTLY as printed in the CSV. Do not tidy or normalise it.
  If several columns hold the same quantity under different names, list them all in
  `symbols`, most representative first.
- `printed_symbol` is the notation the paper itself uses when the header notes reveal it
  (e.g. column `P_t_kips` is printed as "Pt"). Empty when you cannot tell.
- `name` is a short plain-language name (≤ 40 characters). `definition` is one sentence
  saying what the quantity is and how it was obtained.
- `unit` is the unit as the paper reports it ("kips", "in", "ksi", "" for a ratio).
  `quantity_kind` is one of: length, force, stress, moment, area, angle, flow, ratio,
  percentage, count, category.
- `role` says what the quantity does in the experiment:
    measured_output   — the experimental result the study exists to produce
    specimen_parameter — a dimension or property of the test specimen
    material_property — a measured property of the steel
    derived_ratio     — a nondimensional ratio computed from other quantities
    test_condition    — how the test was set up (loading condition, restraint, span)
    predicted_value   — a capacity computed from a code equation or an analysis
    identifier        — a specimen label or grouping key
- `availability` says how directly the paper gives it:
    direct    — it is its own column in a table
    implied   — a single value stated in a header note or footnote rather than a column
                (e.g. "N = 2.625 in for all specimens in this table")
    inferred  — obtainable only with outside knowledge or by reading it off a figure
    simulated — produced by a model or a code equation rather than measured
  Use `evidence` to say where you found it: the table label and page, or the note.
- `table_tags` lists the tag of every table the quantity appears in, exactly as given.

Be complete but do not invent: if the tables do not report a quantity, it does not belong
in the inventory. Do not list a quantity twice under different names.
"""

const INVENTORY_ASK = "Inventory every quantity this paper reports, in the required JSON format."

sstr(desc) = Dict{String,Any}("type" => "string", "description" => desc)
sarr(desc) = Dict{String,Any}("type" => "array", "description" => desc, "items" => Dict{String,Any}("type" => "string"))

const QUANTITY_KINDS = ["length", "force", "stress", "moment", "area", "angle", "flow", "ratio", "percentage", "count", "category"]
const ROLES = ["measured_output", "specimen_parameter", "material_property", "derived_ratio", "test_condition", "predicted_value", "identifier"]
const AVAILABILITY = ["direct", "implied", "inferred", "simulated"]

const VARIABLE_SCHEMA = Dict{String,Any}(
    "type" => "object", "additionalProperties" => false,
    "required" => ["symbols", "printed_symbol", "name", "definition", "unit", "quantity_kind",
                   "role", "availability", "evidence", "table_tags", "note"],
    "properties" => Dict{String,Any}(
        "symbols" => sarr("Column name(s) exactly as printed in the CSV, most representative first"),
        "printed_symbol" => sstr("The paper's own notation, e.g. \"Pt\"; empty if unknown"),
        "name" => sstr("Short plain-language name, ≤ 40 characters"),
        "definition" => sstr("One sentence: what it is and how it was obtained"),
        "unit" => sstr("Unit as the paper reports it; empty for a dimensionless ratio"),
        "quantity_kind" => Dict{String,Any}("type" => "string", "enum" => QUANTITY_KINDS),
        "role" => Dict{String,Any}("type" => "string", "enum" => ROLES),
        "availability" => Dict{String,Any}("type" => "string", "enum" => AVAILABILITY),
        "evidence" => sstr("Where it is given: table label and page, or the header note"),
        "table_tags" => sarr("Tag of every table it appears in"),
        "note" => sstr("Short caveat; empty when there is none")))

const INVENTORY_SCHEMA = Dict{String,Any}(
    "type" => "object", "additionalProperties" => false,
    "required" => ["code_tag", "citation", "year", "title", "experiment", "variables"],
    "properties" => Dict{String,Any}(
        "code_tag" => sstr("The paper's code tag, copied from the input"),
        "citation" => sstr("Author and year as cited, e.g. \"Cain, D.E. (1995)\""),
        "year" => sstr("Four-digit year"),
        "title" => sstr("Paper title"),
        "experiment" => sstr("One sentence: what was physically tested and how"),
        "variables" => Dict{String,Any}("type" => "array", "items" => VARIABLE_SCHEMA,
                                        "description" => "Every distinct quantity the paper reports")))

"""
    Inventory

Pass-1 result for one paper: the parsed JSON plus the paper it came from.
"""
struct Inventory
    paper::Paper
    data::Dict{String,Any}
end
code_tag(inv::Inventory) = String(get(inv.data, "code_tag", inv.paper.code_tag))
variables(inv::Inventory) = get(inv.data, "variables", Any[])
Base.show(io::IO, inv::Inventory) = print(io, "Inventory(", code_tag(inv), ", ",
    length(variables(inv)), " variables from ", length(inv.paper.tables), " tables)")

"""
    ask_inventory(client, paper; model, effort, max_tokens, fallbacks) -> (Dict, resp)
"""
function ask_inventory(client::Client, p::Paper; model=DEFAULT_MODEL, effort="high",
                       max_tokens::Int=16_000, fallbacks::Bool=true, sample_rows::Int=3)
    digest = paper_digest(p; sample_rows)
    content = Any[
        Dict{String,Any}("type" => "text", "text" => "<paper_tables>\n" * digest * "\n</paper_tables>"),
        Dict{String,Any}("type" => "text", "text" => INVENTORY_ASK),
    ]
    output_config = Dict{String,Any}("format" => Dict{String,Any}("type" => "json_schema", "schema" => INVENTORY_SCHEMA))
    effort === nothing || (output_config["effort"] = String(effort))
    body = Dict{String,Any}("model" => String(model), "max_tokens" => max_tokens,
        "system" => INVENTORY_SYSTEM,
        "messages" => Any[Dict{String,Any}("role" => "user", "content" => content)],
        "output_config" => output_config)
    fallbacks && (body["fallbacks"] = "default")
    return ask_json(client, body; betas=betas_for(fallbacks))
end

"""
    build_inventories(papers, client, out; resume=true, kwargs...) -> Vector{Inventory}

Pass 1 over every paper. Each inventory is written to `out/_inventories/<code>.json`;
with `resume=true` a paper that already has one is not asked again.
"""
function build_inventories(papers::Vector{Paper}, client::Client, out::AbstractString;
                           resume::Bool=true, usage_log::Union{Nothing,AbstractString}=nothing, kwargs...)
    dir = joinpath(out, "_inventories")
    mkpath(dir)
    invs = Inventory[]
    for p in papers
        f = joinpath(dir, p.code_tag * ".json")
        if resume && isfile(f)
            @info "inventory exists; reusing" paper = p.code_tag
            push!(invs, Inventory(p, JSON.parsefile(f)))
            continue
        end
        @info "pass 1 — inventory" paper = p.code_tag tables = length(p.tables)
        data, resp = ask_inventory(client, p; kwargs...)
        usage_log === nothing || log_usage!(usage_log, p.code_tag, "inventory", usage_tuple(resp))
        haskey(data, "code_tag") && isempty(strip(String(data["code_tag"]))) && (data["code_tag"] = p.code_tag)
        open(f, "w") do io
            JSON.print(io, data, 2)
        end
        inv = Inventory(p, data)
        @info "  found $(length(variables(inv))) variables"
        push!(invs, inv)
    end
    return invs
end

function log_usage!(dir::AbstractString, subject::AbstractString, what::AbstractString, u::NamedTuple)
    mkpath(dir)
    entry = Dict("time" => Dates.format(now(), "yyyy-mm-ddTHH:MM:SS"), "subject" => subject, "pass" => what,
                 "model" => u.model, "input_tokens" => u.input_tokens, "output_tokens" => u.output_tokens,
                 "cache_read_input_tokens" => u.cache_read_input_tokens,
                 "cache_creation_input_tokens" => u.cache_creation_input_tokens,
                 "cost_usd_estimate" => round(estimate_cost(u); digits=4))
    open(joinpath(dir, "usage.jsonl"), "a") do io
        println(io, JSON.json(entry))
    end
    return estimate_cost(u)
end
