"""
    DataHarmonizer

Module 4 (Harmonization) of the SteelData Initiative pipeline. Standalone: it reads a
folder of extracted data CSVs, one sub-folder per paper, and needs nothing else.

Two passes, so the work grows with the number of papers instead of exploding:

1. **Inventory** – one API call per paper. Reads that paper's CSV headers, column
   definitions and a few sample rows, and lists every measured or reported quantity under
   the paper's own symbol, with its meaning, unit, the table tags it appears in, and how
   directly it is available.
2. **Cluster** – one API call for the whole set, seeing only the compact inventories.
   Groups the variables by physical meaning into canonical rows, picks one canonical unit
   per row and records any conversion.

Outputs a concordance: `common_variables.csv`, `variable_inventory.csv`, the raw
`harmonization.json` and a self-contained HTML page.

Entry point: [`harmonize_papers`](@ref).
"""
module DataHarmonizer

using Dates, Logging
using HTTP, JSON

export harmonize_papers, build_inventories, cluster_inventories, render_concordance
export Paper, Inventory, Concordance, collect_papers

include("csv.jl")
include("anthropic.jl")
include("sources.jl")
include("units.jl")
include("inventory.jl")
include("cluster.jl")
include("output.jl")
include("html.jl")
include("run.jl")

end # module
