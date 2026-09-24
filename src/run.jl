# One-call driver.

"""
    harmonize_papers(input; out=nothing, resume=true, model="claude-opus-5", effort="high",
                     fallbacks=true, api_key=nothing, client=nothing, sample_rows=3) -> Concordance

Harmonize a folder of extracted data CSVs, typically one sub-folder per paper.

Two passes: an inventory per paper, then one clustering call over the inventories. Writes
into `out` (default `<input>_harmonized`):

- `common_variables.csv` — one row per canonical variable, one column per paper;
- `variable_inventory.csv` — the long form, one row per paper per variable;
- `source_tables.csv` — every table read, so a tag resolves to a file;
- `concordance.html` — the page;
- `_inventories/` — the per-paper inventories, `harmonization.json`, `usage.jsonl`.

With `resume=true` a paper that already has an inventory is not asked again, so adding a
paper to the set costs one inventory call plus the re-cluster.
"""
function harmonize_papers(input::AbstractString; out::Union{Nothing,AbstractString}=nothing,
                          resume::Bool=true, model=DEFAULT_MODEL, effort="high", fallbacks::Bool=true,
                          api_key=nothing, client::Union{Nothing,Client}=nothing, sample_rows::Int=3,
                          recursive::Bool=true, api_timeout::Integer=1800)
    input = abspath(rstrip(input, ['/', '\\']))
    out = out === nothing ? input * "_harmonized" : abspath(out)
    mkpath(out)
    logdir = joinpath(out, "_inventories")
    mkpath(logdir)

    papers = collect_papers(input; recursive)
    @info "Harmonizing" papers = length(papers) tables = sum(length(p.tables) for p in papers) out
    c = client === nothing ? Client(; api_key, timeout=api_timeout) : client

    invs = build_inventories(papers, c, out; resume, usage_log=logdir, model, effort, fallbacks, sample_rows)

    hfile = joinpath(logdir, "harmonization.json")
    parsed = if resume && isfile(hfile) && !any_inventory_newer(logdir, hfile)
        @info "clustering exists and no inventory is newer; reusing" file = basename(hfile)
        JSON.parsefile(hfile)
    else
        p, resp = cluster_inventories(invs, c; model, effort, fallbacks)
        log_usage!(logdir, "ALL", "cluster", usage_tuple(resp))
        open(hfile, "w") do io
            JSON.print(io, p, 2)
        end
        p
    end

    con = build_concordance(parsed, invs, papers, out)
    write_common_variables(con)
    write_variable_inventory(con)
    write_source_tables(con)
    html = joinpath(out, "concordance.html")
    write(html, render_concordance(con))

    total = run_cost(logdir)
    @info "Done" canonical_variables = length(con.variables) checks = length(con.checks) cost_usd = round(total; digits=2)
    isempty(con.checks) || @warn "checks to review" first(con.checks, 5)
    println("\n", sprint(show, con), "\n  page: ", html)
    return con
end

"""
    any_inventory_newer(logdir, hfile) -> Bool

True when a per-paper inventory was written after the clustering was, meaning the
clustering is stale and has to be redone.
"""
function any_inventory_newer(logdir::AbstractString, hfile::AbstractString)
    hm = mtime(hfile)
    for f in readdir(logdir; join=true)
        endswith(f, ".json") && basename(f) != basename(hfile) && mtime(f) > hm && return true
    end
    return false
end

"""
    run_cost(logdir) -> Float64

Total estimated spend recorded in `usage.jsonl`.
"""
function run_cost(logdir::AbstractString)
    f = joinpath(logdir, "usage.jsonl")
    isfile(f) || return 0.0
    total = 0.0
    for line in eachline(f)
        isempty(strip(line)) && continue
        try
            total += Float64(get(JSON.parse(line), "cost_usd_estimate", 0.0))
        catch
        end
    end
    return total
end
