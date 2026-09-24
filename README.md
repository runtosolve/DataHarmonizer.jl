# DataHarmonizer.jl

**Module 4 (Harmonization) of the SteelData Initiative pipeline.**

DataExtractor turns each research PDF into data-table CSVs. Different papers measure the
same physical thing under different names: one calls it `P_t_kips`, another
`Pt_kips_per_web`, a third just "tested load". This module reads a set of papers' CSVs and
produces a **Summary Table of Common Measured Variables**: one row per physical quantity,
one column per paper, on one unit, with the percentage of papers that carry it and the tag
of the table each value came from.

It is standalone. It reads only the extracted CSVs, and needs neither the PDFs nor any
other module installed.

---

## 1. One-time setup (Windows PowerShell)

```powershell
cd "C:\Users\OSAMA BIN ELI\OneDrive\Desktop\RunToSolve\SteelDataInitiative\DataHarmonizer.jl"
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

Or, once it is on GitHub:

```powershell
julia -e "using Pkg; Pkg.add(url=\"https://github.com/runtosolve/DataHarmonizer.jl\")"
```

The API key is found the same way as the other modules: `ANTHROPIC_API_KEY` in the
environment, or in the `.env` file in the `SteelDataInitiative` folder.

---

## 2. Running it

Point it at a folder holding the papers you want to compare. One sub-folder per paper is
the normal shape, but a flat folder works too.

```powershell
cd "C:\Users\OSAMA BIN ELI\OneDrive\Desktop\RunToSolve\SteelDataInitiative\DataHarmonizer.jl"
julia --project=.
```

```julia
using DataHarmonizer
harmonize_papers("C:/path/to/11,211,230 Flange")
```

Results go to `<input>_harmonized` next to the input, or wherever `out=` says. Open
`concordance.html` by double-clicking it.

**Choose papers that belong together.** The whole point is overlap, so a set drawn from
one topic gives a useful table. A set spanning bolted connections and airtightness
harmonizes to almost nothing, which tells you nothing.

**Word documents are skipped.** Extraction guides, references and PDFs in the folder are
ignored, as are lock files and byte-identical duplicate CSVs. Only the data CSVs are read.

---

## 3. What you get

```
11,211,230 Flange_harmonized/
├── concordance.html          the page: descriptions, units, availability, marks, tags
├── common_variables.csv      one row per canonical variable, one column per paper
├── variable_inventory.csv    long form: one row per paper per variable
├── source_tables.csv         every table read, so a tag resolves to a file
└── _inventories/
    ├── MBMA_9408.json        that paper's raw variable inventory (pass 1)
    ├── harmonization.json    the clustering answer (pass 2)
    └── usage.jsonl           tokens and estimated cost per call
```

### The marks

| Mark | Meaning |
|---|---|
| **Yes** | reported as its own column in a table |
| **Yes (Implied)** | a single value stated in a header note or footnote, not a column |
| **Yes (Inferred)** | obtainable only with outside context, or read off a figure |
| **Yes (Simulated)** | produced by a model or a code equation rather than measured |
| *(empty)* | not addressed in that paper |

### Reading the availability bar

The fraction counts every paper where the variable can be obtained at all. The bar splits
that into **direct** (green) and **qualified** (orange). A row that is 100% available but
mostly implied is weaker than one that is 100% direct, and a single percentage hides the
difference. The row also records `n_direct` and `n_qualified` in the CSV.

### Units

One canonical unit per row, the one most common across the sources, with its SI
equivalence beside it. A paper reporting in another unit gets a conversion chip such as
`× 25.4`, and `common_variables.csv` records the factor. Conversions the module cannot
verify are flagged under "Automatic checks" rather than applied silently.

### Traceability

Every mark carries the tag of the table it came from, matching the tag line written into
the CSV at extraction. `source_tables.csv` resolves each tag to a file, a table label and
a page range in the original report.

---

## 4. How it works

Two passes, so the work grows with the number of papers instead of exploding.

**Pass 1, one call per paper.** The model reads that paper's CSV headers, column
definitions, unit lines, notes and a few sample rows, then lists every distinct quantity
the paper reports under the paper's own symbol, with its meaning, unit, role, availability
and the tags of the tables it appears in. The data rows themselves are not sent, because
harmonization is about the columns.

**Pass 2, one call for the set.** The model sees only the inventories, never the raw
tables, and clusters the variables across papers by physical meaning.

Each inventory is written to `_inventories/`, so with `resume=true` (the default) adding a
paper later costs one inventory call and one re-cluster, not a redo of everything.

A typical three-paper set sends about 5,000 tokens in pass 1 and 6,000 in pass 2, so a run
costs well under a dollar.

### After the run, read the checks

Two lists at the bottom of the page deserve a look before the table is used:

- **Judgement calls to review** are the model's own: merges it was unsure about, symbols
  whose meanings differed subtly, quantities it deliberately kept apart.
- **Automatic checks** are this module's: a table tag that does not match any table on
  disk, a unit it could not convert, a paper listed twice in one row, or an inventoried
  variable that never reached a canonical row.

---

## 5. Options

| keyword | default | meaning |
|---|---|---|
| `out` | `<input>_harmonized` | where to write results |
| `resume` | `true` | reuse existing per-paper inventories |
| `model` | `"claude-opus-5"` | any Messages API model id |
| `effort` | `"high"` | `"medium"` or `"low"` for cheaper runs |
| `sample_rows` | `3` | data rows shown per table in pass 1 |
| `recursive` | `true` | search sub-folders for CSVs |
| `fallbacks` | `true` | server-side refusal fallback |
| `api_key` | from env / `.env` | override the key |

To redo a single paper's inventory, delete its file from `_inventories/` and run again.
To redo everything, pass `resume=false`.

---

## 6. Tests

```powershell
cd "C:\Users\OSAMA BIN ELI\OneDrive\Desktop\RunToSolve\SteelDataInitiative\DataHarmonizer.jl"
julia --project=. -e "using Pkg; Pkg.test()"
```

Offline tests cover the tolerant header parser against both header conventions, unit
conversion and SI equivalences, the availability arithmetic, tag resolution and the CSV
and HTML writers. The live test harmonizes a small set through the API and is opt-in:

```powershell
$env:DATAHARMONIZER_LIVE = "1"
julia --project=. -e "using Pkg; Pkg.test()"
```
