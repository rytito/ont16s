# Contributing

> 🌐 [Español (versión principal)](CONTRIBUTING.md) · **English**

## Before changing main.nf or nextflow.config

These two files took a dozen iterations to get working against Nextflow's
strict parser. Before opening a PR that touches them, confirm the script still
compiles:

```bash
nextflow run main.nf --help
```

Then run the cheapest real test, which needs no GPU:

```bash
nextflow run main.nf \
    -profile slurm,conda -params-file conf/site.yml \
    --step from_fastq --fastq_dir <a-few-fastqs> --subsample 5000 \
    --outdir smoke_test
```

`results/06_tables/` with non-empty TSVs means the change is safe.

## Settings not to "tidy"

Each of these exists because of a specific failure. `docs/GOTCHAS.md` records
the symptom for each.

- `--no-trim` in `DORADO_BASECALL` — barcodes must survive to the demux step
- `samtools quickcheck -u` after basecalling — Dorado can exit 0 on a truncated write
- `find`-based traversal of the demux tree — the layout is nested and includes an `unknown` level
- `stageInMode = 'symlink'` — copying ~90 GB of POD5 exceeds typical scratch quotas
- No `PATH` in the `env {}` block — `env` exports run after `beforeScript` and would overwrite it
- `--nodes=1` in the GPU `clusterOptions` — VSC rejects GPU jobs without it
- 48 GB for `cpu_med` — SILVA's minimap2 index OOMs at 16 GB
- `asInt()` around numeric params — CLI params arrive as Strings

## Adding a database

Extend `bin/setup_databases.sh` and document the memory requirement. Any
database with over ~1M references needs the `cpu_med` allocation raised.


