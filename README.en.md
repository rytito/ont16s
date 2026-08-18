# ont16s

> 🌐 [Español (versión principal)](README.md) · **English**

Nextflow pipeline for Oxford Nanopore full-length 16S rRNA sequencing: from
raw POD5 signal to a `phyloseq` object, in one command.

Built and validated for **Kit 14 chemistry** (R10.4.1 / FLO-MIN114) with the
**16S Barcoding Kit 24 V14 (SQK-16S114.24)**, where basecalling is switched
**off** on the sequencer and performed on an HPC cluster instead.

```
POD5  ──▶  Dorado basecall      (GPU, sup@v5.2.0, --no-trim)
      ──▶  Dorado demux         (kit-aware, --barcode-both-ends)
      ──▶  samtools fastq       (barcode tags preserved)
      ──▶  chopper              (q≥10, 1200–1800 bp)
      ──▶  seqkit sample        (depth normalisation)
      ──▶  Emu abundance        (one pass per database)
      ──▶  Emu combine          (taxa × samples tables)
      ──▶  phyloseq             (.rds + QC tables + plots)
```

## Why this and not wf-16s

ONT's own `wf-16s` is a fine workflow with a nicer HTML report. This pipeline
differs in three ways that matter for research use:

- **Emu instead of Kraken2.** Emu resolves ambiguous reads with
  expectation-maximisation over full-length alignments. ONT's own mock-community
  benchmarking found Kraken2 produced substantial false-positive taxa where
  alignment-based methods did not.
- **Any reference database.** Includes a converter for **GTDB r226**, which
  fixes obsolete genus names (*Lactobacillus* → *Lacticaseibacillus* etc.) and
  gives honest placeholder names for uncultured organisms rather than forcing
  them onto distant named relatives.
- **Plain TSVs and a phyloseq object**, not a report you have to scrape.

Running both and comparing is a reasonable strategy: agreement between an
EM-based and a k-mer-based method on different reference sets is strong
evidence, and disagreement flags exactly the taxa you should not put in a
figure.

## Quick start

```bash
# 1. Environments and databases (once per site)
bash bin/setup_environments.sh /shared/conda_envs
micromamba activate /shared/conda_envs/emu
bash bin/setup_databases.sh /shared/databases gtdb

# 2. Site configuration
cp conf/site.yml.example conf/site.yml
$EDITOR conf/site.yml          # paths, account, databases

# 3. Run
nextflow run main.nf \
    -profile slurm,conda \
    -params-file conf/site.yml \
    --step all \
    --pod5_dir /project/myrun/pod5 \
    --metadata metadata.tsv \
    --outdir results
```

**Run it inside `tmux`.** Nextflow runs in the foreground and dies with your
SSH session otherwise — `-resume` recovers, but you lose the current stage.

```bash
tmux new -s ont16s
# ... launch the pipeline ...
# Ctrl+B then D to detach; tmux attach -t ont16s to return
```

## Stages

Selected with `--step`. Nextflow 26.04's strict syntax removed `-entry`.

| Starting from | Command |
|---|---|
| POD5 (full run) | `--step all --pod5_dir <dir>` |
| An existing `calls.bam` | `--step from_bam --calls_bam calls.bam` |
| Per-sample FASTQ | `--step from_fastq --fastq_dir <dir>` |

`from_bam` is what you want after a demux or profiling failure — it skips the
expensive GPU stage entirely.

## Output

```
results/
├── 01_basecall/        tool versions
├── 02_demux/           barcoding summary
├── 03_filtered/        per-barcode FASTQ, quality/length filtered
├── 04_subsampled/      depth-normalised FASTQ
├── 05_emu/<db>/        per-sample abundance tables
├── 06_tables/          <db>_emu-combined-{species,genus,family}[-counts].tsv
├── 07_phyloseq/<db>/   phyloseq.rds, alpha diversity, ordination, plots
├── qc/                 read stats, reads per barcode
└── pipeline_info/      timeline, report, trace, DAG
```

Load the object directly:

```r
ps <- readRDS("results/07_phyloseq/gtdb/phyloseq.rds")
```

## Metadata

A TSV with a `SampleID` column matching the barcode names. See
`assets/metadata_template.tsv`. Any other columns become sample variables, and
categorical ones are automatically tested with PERMANOVA.

```tsv
SampleID	sample_name	group	replicate
barcode01	S01	control	1
barcode02	S02	treatment	1
```

Without `--metadata` the pipeline stops after `06_tables`.

## Requirements

- Nextflow **≥ 26.04** and Java 11+ (`module load Java/...` on most clusters)
- An NVIDIA GPU with tensor cores. **P100/GP100 are not supported by Dorado.**
- Dorado ≥ 2.0 (static binary; deliberately not containerised)
- conda/micromamba, or Apptainer

## Documentation

- [`docs/USAGE.en.md`](docs/USAGE.en.md) — parameters, profiles, cluster setup, runtimes
- [`docs/GOTCHAS.en.md`](docs/GOTCHAS.en.md) — failure modes we hit, and how to spot them

**Read `GOTCHAS.md` before your first real run.** Several documented failures
report success while silently losing data.

## Citation

Cite the underlying tools: Dorado (Oxford Nanopore), Emu (Curry *et al.* 2022,
*Nature Methods*), minimap2 (Li 2018), chopper/nanoq, seqkit, phyloseq
(McMurdie & Holmes 2013), plus your reference database **with its release
number** — GTDB r226, SILVA 138.2, or NCBI 16S RefSeq. Taxonomy differs
substantially between them, so the release matters.

If you report GTDB results, note in your methods that genus suffixes such as
`Clostridium_S` and `Clostridium_B` denote distinct genera split from a
polyphyletic NCBI genus. Reviewers unfamiliar with GTDB read them as typos.

## Funding and credits

This pipeline was developed within the **MicroAndes** project — *Harnessing
microbes to strengthen Andean communities of micro-producers of fermented
foods* — a **VLIR-UOS Short Initiative** (KU Leuven project
[3M250529](https://research.kuleuven.be/portal/nl/project/3M250529),
funding reference PE2025SIN468A101, 2025–2027).

- **Coordinating institution:** KU Leuven — Laboratory of Molecular
  Bacteriology, Rega Institute 
- **Partner institutions:** Universidad Nacional del Centro del Perú (UNCP)
  and Andean micro-producer communities
- **Funding:** VLIR-UOS (Vlaamse Interuniversitaire Raad), Short Initiatives
  programme

## Licence

MIT — see [`LICENSE`](LICENSE).
