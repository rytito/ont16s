# Changelog

> 🌐 [Español (versión principal)](CHANGELOG.md) · **English**

## 1.0.0

First release. Validated end to end on KU Leuven wICE with real SQK-16S114.24
data: 24 barcodes, 2.4M reads, ~86 GB POD5.

### Validated

- `--step all` — Dorado basecalling on `gpu_h100` through to combined tables
- `--step from_fastq` — subsample, QC, multi-database Emu profiling
- GTDB r226 (custom-built) and SILVA 138.2 in the same run
- SLURM submission, resource labels, retry-with-more-memory on OOM
- phyloseq object generation with depth filtering and PERMANOVA

### Measured

| Stage | Scale | Time |
|---|---|---|
| Basecalling `sup@v5.2.0` | 2.4M reads, 1× H100 | ~1 h (2.8e7 samples/s, 54 GB peak RSS) |
| Demultiplexing | 2.4M reads, 16 cores | ~8 min |
| Emu, GTDB | 20k reads/sample | ~4 min/sample |
| Emu, SILVA | 20k reads/sample | ~10 min/sample, 48 GB |

### Compatibility

Requires **Nextflow ≥ 26.04**, whose strict syntax this targets: `--step`
rather than `-entry`, `error` rather than `exit`, `if`/`else if` rather than
`switch`, no `workflow.onComplete`, and closures around `publishDir`
expressions that reference input variables.

Pin the engine for reproducibility:

```bash
export NXF_VER=26.04.6
```

### Known limitations

- No `nf-schema` validation; numeric params are coerced manually via `asInt()`
- Dorado is not containerised — set `--dorado_bin`
- `unclassified` reads are published but not profiled
- No MultiQC summary
