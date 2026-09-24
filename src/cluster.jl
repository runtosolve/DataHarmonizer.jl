# Pass 2: one call for the whole set. Cluster the per-paper inventories into canonical
# variables by physical meaning, and put each row on one unit.

const CLUSTER_SYSTEM = """
You are harmonizing several structural-engineering papers into one "Summary Table of
Common Measured Variables".

You are given a compact inventory per paper: every quantity that paper reports, under the
paper's own symbol, with its meaning, unit, role, availability and the tags of the tables
it appears in. You never see the raw data.

Cluster the variables ACROSS papers by physical meaning, not by name. "Tested load",
"P_t_kips" and "Pt_kips_per_web" collapse into one canonical row when they are the same
physical quantity. Two quantities that merely sound alike do not: a MEASURED failure load
and a CODE-PREDICTED capacity are different rows, as are a web thickness and a flange
thickness.

For each canonical row:
- `name`: a short canonical name in plain words (≤ 42 characters), not any one paper's symbol.
- `description`: one sentence a reader outside the field can follow, saying what the
  quantity is and why it is measured.
- `canonical_unit`: one unit for the whole row, the one most common across the sources.
  Use "—" for a dimensionless ratio, "%" for a percentage, "text" for a label.
- `quantity_kind` and `role`: carry over from the members; if members disagree, choose the
  one that fits the canonical meaning.
- `members`: one entry per paper that has this quantity, with that paper's own `symbol`
  exactly as printed, its `unit` as reported, its `availability`, its `evidence` and its
  `table_tags`. A paper without the quantity is simply absent from `members` — do not add
  an entry for it.
- `conversion_needed`: true when at least one member reports in a unit other than the
  canonical one.

Ordering and judgement:
- Put the rows that matter most to a researcher first: the measured outputs of the
  experiments, then the specimen parameters and material properties they depend on, then
  derived ratios, predicted values, test conditions and identifiers.
- A row shared by more papers is more useful than one held by a single paper, so within a
  role, order by how many papers carry it.
- Include single-paper variables too, at the end of their role group. They are what a
  reader needs in order to see what is NOT comparable.
- In `notes`, record any judgement call a reviewer should check: a merge you were unsure
  about, a unit that had to be converted, a symbol whose meaning differed subtly between
  papers, or a quantity you deliberately kept separate despite a similar name.
"""

const CLUSTER_ASK = "Harmonize these inventories into canonical variables, in the required JSON format."

const MEMBER_SCHEMA = Dict{String,Any}(
    "type" => "object", "additionalProperties" => false,
    "required" => ["code_tag", "symbol", "unit", "availability", "evidence", "table_tags", "note"],
    "properties" => Dict{String,Any}(
        "code_tag" => sstr("The paper's code tag"),
        "symbol" => sstr("That paper's own column name, exactly as printed"),
        "unit" => sstr("Unit as that paper reports it"),
        "availability" => Dict{String,Any}("type" => "string", "enum" => AVAILABILITY),
        "evidence" => sstr("Table label and page, or the note it came from"),
        "table_tags" => sarr("Tags of the tables it appears in"),
        "note" => sstr("Short caveat; empty when there is none")))

const CANONICAL_SCHEMA = Dict{String,Any}(
    "type" => "object", "additionalProperties" => false,
    "required" => ["name", "description", "canonical_unit", "quantity_kind", "role", "conversion_needed", "members"],
    "properties" => Dict{String,Any}(
        "name" => sstr("Canonical name in plain words, ≤ 42 characters"),
        "description" => sstr("One sentence: what it is and why it is measured"),
        "canonical_unit" => sstr("One unit for the row; \"—\", \"%\" or \"text\" where appropriate"),
        "quantity_kind" => Dict{String,Any}("type" => "string", "enum" => QUANTITY_KINDS),
        "role" => Dict{String,Any}("type" => "string", "enum" => ROLES),
        "conversion_needed" => Dict{String,Any}("type" => "boolean", "description" => "true if any member reports another unit"),
        "members" => Dict{String,Any}("type" => "array", "items" => MEMBER_SCHEMA,
                                      "description" => "One per paper that has this quantity")))

const CLUSTER_SCHEMA = Dict{String,Any}(
    "type" => "object", "additionalProperties" => false,
    "required" => ["set_title", "summary", "canonical_variables", "notes"],
    "properties" => Dict{String,Any}(
        "set_title" => sstr("Short title for what this set of papers has in common, ≤ 60 characters"),
        "summary" => sstr("Two sentences: what the papers share and where they diverge"),
        "canonical_variables" => Dict{String,Any}("type" => "array", "items" => CANONICAL_SCHEMA,
                                                  "description" => "The harmonized rows, most useful first"),
        "notes" => sarr("Judgement calls a reviewer should check")))

"""
    inventory_digest(inv::Inventory) -> String

The compact form of one inventory that the clustering pass reads.
"""
function inventory_digest(inv::Inventory)
    d = inv.data
    io = IOBuffer()
    println(io, "<paper code=\"", code_tag(inv), "\">")
    println(io, "citation: ", get(d, "citation", ""), "   year: ", get(d, "year", ""))
    println(io, "title: ", get(d, "title", inv.paper.title))
    println(io, "experiment: ", get(d, "experiment", ""))
    println(io, "variables:")
    for v in variables(inv)
        syms = get(v, "symbols", Any[])
        println(io, "  - symbol: ", isempty(syms) ? "?" : join(syms, ", "),
                "  | name: ", get(v, "name", ""),
                "  | unit: ", get(v, "unit", ""),
                "  | kind: ", get(v, "quantity_kind", ""),
                "  | role: ", get(v, "role", ""),
                "  | availability: ", get(v, "availability", ""))
        println(io, "      definition: ", get(v, "definition", ""))
        println(io, "      evidence: ", get(v, "evidence", ""), "  | tables: ", join(get(v, "table_tags", Any[]), ", "))
        n = String(get(v, "note", ""))
        isempty(strip(n)) || println(io, "      note: ", n)
    end
    println(io, "</paper>")
    return String(take!(io))
end

"""
    cluster_inventories(invs, client; model, effort, max_tokens, fallbacks) -> (Dict, resp)

Pass 2: one call over all inventories.
"""
function cluster_inventories(invs::Vector{Inventory}, client::Client; model=DEFAULT_MODEL, effort="high",
                             max_tokens::Int=32_000, fallbacks::Bool=true)
    isempty(invs) && throw(ArgumentError("no inventories to cluster"))
    digest = join((inventory_digest(i) for i in invs), "\n\n")
    content = Any[
        Dict{String,Any}("type" => "text", "text" => "<inventories papers=\"" * string(length(invs)) * "\">\n" * digest * "\n</inventories>"),
        Dict{String,Any}("type" => "text", "text" => CLUSTER_ASK),
    ]
    output_config = Dict{String,Any}("format" => Dict{String,Any}("type" => "json_schema", "schema" => CLUSTER_SCHEMA))
    effort === nothing || (output_config["effort"] = String(effort))
    body = Dict{String,Any}("model" => String(model), "max_tokens" => max_tokens,
        "system" => CLUSTER_SYSTEM,
        "messages" => Any[Dict{String,Any}("role" => "user", "content" => content)],
        "output_config" => output_config)
    fallbacks && (body["fallbacks"] = "default")
    @info "pass 2 — clustering" papers = length(invs) approx_input_tokens = cld(sizeof(digest), 4)
    return ask_json(client, body; betas=betas_for(fallbacks))
end
