# Usage

> 🌐 [Español (versión principal)](USAGE.md) · **English**

## One-time site setup

### Java and Nextflow

Java is not on the default `PATH` on most clusters, and module loads do not
persist across logins:

```bash
module spider Java
module load Java/25.36        # use whatever module spider reports
java -version
```

Then Nextflow:

```bash
mkdir -p ~/software && cd ~/software
curl -s https://get.nextflow.io | bash
./nextflow -version           # needs >= 26.04
```

Cleaner for a shared group, because it bundles its own JRE and pins the engine
version for everybody:

```bash
micromamba create -y -p /shared/conda_envs/nextflow -c conda-forge -c bioconda nextflow
```

Pin the version regardless — Nextflow 26.04 introduced breaking syntax changes,
and the next release may too:

```bash
export NXF_VER=26.04.6
```

### Dorado

Dorado ships as a self-contained tarball with its own CUDA runtime, which makes
it the most robust option on a shared cluster: no module conflicts, no container
GPU passthrough.

```bash
cd /shared/software
VER=2.1.0
wget https://cdn.oxfordnanoportal.com/software/analysis/dorado-${VER}-linux-x64.tar.gz
tar -xzf dorado-${VER}-linux-x64.tar.gz && rm dorado-${VER}-linux-x64.tar.gz

mkdir -p /shared/software/dorado_models
export DORADO_MODELS_DIRECTORY=/shared/software/dorado_models
/shared/software/dorado-${VER}-linux-x64/bin/dorado download \
    --model dna_r10.4.1_e8.2_400bps_sup@v5.2.0 \
    --models-directory /shared/software/dorado_models
```

Download the model **on a login node**. Compute nodes may have no internet, and
a GPU job that dies twenty minutes in because it could not fetch a model is
wasted allocation.

**Put Dorado and its models on group storage.** A personal home or data
directory means the pipeline breaks for everyone else when one account changes.

#### Why `sup@v5.2.0`

Dorado 2.x introduced `hac@v6.0.0` for R10.4.1, but ONT released no v6 **SUP**
model for this chemistry. `sup@v5.2.0` remains the most accurate available, and
accuracy matters for species-level 16S assignment.

### Environments and databases

```bash
bash bin/setup_environments.sh /shared/conda_envs
micromamba activate /shared/conda_envs/emu
bash bin/setup_databases.sh /shared/databases gtdb
```

`setup_environments.sh` installs `pod5` and `NanoPlot` via pip deliberately: the
bioconda `pod5` recipe pins `polars >=0.19,<1.dev0`, which no longer resolves
against modern Python and breaks the whole solve.

### Shell environment

```bash
cat >> ~/.bashrc <<'EOF'
export NXF_HOME="$SCRATCH/.nextflow"
export NXF_WORK="$SCRATCH/nxf_work"
export APPTAINER_CACHEDIR="$SCRATCH/.apptainer/cache"
export APPTAINER_TMPDIR="$SCRATCH/.apptainer/tmp"
EOF
```

Container images and Nextflow's `work/` directory are multi-GB. Without these
they land in your home directory and exhaust its quota.

## Storage planning

A full MinION 16S run needs roughly:

| Item | Size |
|---|---|
| POD5 input | ~85 GB |
| `calls.bam` | ~6 GB |
| demux output | ~3 GB |
| Nextflow `work/` | 2–3× intermediates |

**Keep POD5 on project storage** and point `--pod5_dir` at it. The pipeline sets
`stageInMode = 'symlink'` so Nextflow does not duplicate it into `work/`, but
the published outputs still need room. Check your quota before submitting —
exceeding it truncates BAMs while Dorado still reports success.

## Parameters

### Input

| Parameter | Default | Notes |
|---|---|---|
| `--step` | `all` | `all` \| `from_bam` \| `from_fastq` |
| `--pod5_dir` | — | With basecalling off, MinKNOW writes `pod5/`, not `pod5_pass/` |
| `--calls_bam` | — | For `--step from_bam` |
| `--fastq_dir` | — | For `--step from_fastq`; files named `barcodeNN.fastq` |
| `--metadata` | — | TSV with `SampleID`; enables phyloseq output |
| `--outdir` | `results` | |

### Basecalling

| Parameter | Default | Notes |
|---|---|---|
| `--model` | `sup` | Resolves to the best model for the chemistry |
| `--max_reads` | none | Cap for testing |
| `--batchsize_benchmarks` | none | Cached batch-size file; saves ~15 s per job |

### Demultiplexing

| Parameter | Default |
|---|---|
| `--kit` | `SQK-16S114-24` (hyphens, not the dots in ONT's product name) |
| `--barcode_both_ends` | `true` |

In this kit the barcodes sit on the 27F/1492R primers, so **both ends of every
amplicon carry one**. Requiring agreement suppresses index hopping, which
otherwise appears as phantom taxa bleeding between samples. Expect 5–15% of
reads in `unclassified` in exchange — worth it for any comparative study. Set
`false` only if unclassified exceeds ~25%, which suggests degraded amplicon
ends.

### Filtering and depth

| Parameter | Default | Notes |
|---|---|---|
| `--min_qscore` | `10` | |
| `--min_len` / `--max_len` | `1200` / `1800` | 27F/1492R amplicons peak at 1450–1550 bp |
| `--subsample` | `20000` | `0` disables |
| `--seed` | `42` | Reproducible subsampling |
| `--min_reads` | `5000` | Samples below this are dropped from the phyloseq object |

Subsampling is the largest runtime lever. Emu scales with depth: at 90k reads
per sample it took over 20 minutes each, at 20k about four. Relative abundances
are stable well below 20k, so nothing meaningful is lost.

### Taxonomy

| Parameter | Notes |
|---|---|
| `--emu_dbs` | `name:path[,name:path,...]` — profiles against each in turn |

| Database | Use it for | Do not use it for |
|---|---|---|
| **GTDB r226** | Primary taxonomy. Current names, genome-based, honest placeholders | Chloroplast/mitochondrial detection — prokaryote-only |
| **SILVA 138.2** | Quantifying plant/host contamination (labels Chloroplast, Mitochondria) | Species-level calls — widely regarded as unreliable |
| **Emu default** | Comparison with older literature | Anything current. Frozen Sept 2020 |

Running two databases is a cheap confidence measure: a genus at similar
abundance in both is a solid call, one at 30% in one and 2% in the other is a
database artefact. But SILVA needs ~48 GB RAM per task and roughly triples
runtime, so GTDB alone is the sensible default for routine work.

## Profiles

Combine with commas: `-profile vsc_wice,conda`

| Profile | Purpose |
|---|---|
| `standard` | Local execution |
| `slurm` | Generic SLURM; set `--partition_cpu`, `--partition_gpu`, `--account` |
| `vsc_wice` | KU Leuven wICE: `gpu_h100` + `batch_sapphirerapids` |
| `vsc_genius` | KU Leuven Genius: `gpu_v100` (4 cores/GPU ceiling) |
| `conda` | Pre-built conda environments |
| `apptainer` | Containers for everything except Dorado |
| `test` | `--max_reads 20000 --subsample 5000 --min_reads 100` |
| `debug` | Prints hostname, `nvidia-smi`, and `PATH` before each task |

### Partition ceilings

Exceeding the per-GPU core limit gets the job rejected outright.

| Cluster | Partition | Max cores/GPU | Max mem/GPU |
|---|---|---|---|
| wICE | `gpu_h100` | 16 | 187200 MiB |
| wICE | `gpu_a100` | 18 | 126000 MiB |
| Genius | `gpu_v100` | 4 | 84000 MiB |
| Genius | `gpu_p100` | **unusable** | Dorado does not support P100/GP100 |

### Why Dorado is not containerised

GPU passthrough needs `--nv`, host and image driver versions must be compatible,
and the static binary already bundles its CUDA runtime. Containerising it adds
failure modes for no gain. Set `--dorado_bin` instead.

If your site requires full containerisation, add
`apptainer.runOptions = '--nv'`, supply an ONT Dorado image, and test GPU
visibility with `-profile debug` first.

## Measured runtimes

One H100, 24 barcodes, 2.4M reads from ~86 GB of POD5:

| Stage | Time |
|---|---|
| Basecalling `sup@v5.2.0` | ~1 h (2.8e7 samples/s, 54 GB peak RSS) |
| Demultiplexing (16 cores) | ~8 min |
| Emu per sample, 20k reads, GTDB | ~4 min |
| Emu per sample, 20k reads, SILVA | ~10 min, needs 48 GB |

Emu tasks run in parallel, so 24 samples against GTDB complete in roughly the
time of a couple of samples given free nodes.

## Running it safely

```bash
tmux new -s ont16s

module load Java/25.36
nextflow run main.nf \
    -profile vsc_wice,conda \
    -params-file conf/site.yml \
    --step all \
    --pod5_dir /project/myrun/pod5 \
    --metadata metadata.tsv \
    --outdir results
```

Detach with **Ctrl+B** then **D**; reattach with `tmux attach -t ont16s`.

Do **not** use Ctrl+Z on a running pipeline — it suspends the process and leaves
the session lock held, which then blocks `-resume`. Ctrl+C once instead;
Nextflow cancels cleanly and releases the lock.

Monitoring from another shell:

```bash
squeue -M wice -u $USER
ls results/                      # directories appear in stage order
tail -20 .nextflow.log
```

`results/07_phyloseq/` (or `06_tables/` without metadata) means it finished.

## Resuming

```bash
nextflow run main.nf ... -resume
```

Completed tasks are cached and not repeated. After a basecalling success and a
later failure, `--step from_bam --calls_bam results/01_basecall/calls.bam` skips
the GPU stage entirely.
