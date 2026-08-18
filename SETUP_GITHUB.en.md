# Publishing to GitHub

> 🌐 [Español (versión principal)](SETUP_GITHUB.md) · **English**

## 1. Create the repo locally

```bash
cd ont16s
git init
git add .
git commit -m "ont16s v1.0.0: ONT 16S pipeline, POD5 to phyloseq"
git branch -M main
```

`conf/site.yml` is gitignored — only `site.yml.example` is committed, since the
real file holds absolute paths and an account name specific to one cluster.

## 2. Push

```bash
gh repo create ont16s --public --source=. --push
```

Or after creating it in the web UI:

```bash
git remote add origin git@github.com:<user>/ont16s.git
git push -u origin main
git tag -a v1.0.0 -m "First validated release"
git push --tags
```

## 3. Deploy on a cluster as a clone, not a copy

This is the part worth getting right. If the cluster copy and the repo are
separate, they diverge and you end up not knowing which is authoritative.

```bash
cd /shared/pipelines
git clone https://github.com/<user>/ont16s.git
cd ont16s
cp conf/site.yml.example conf/site.yml
$EDITOR conf/site.yml
```

Updates then land with `git pull`, and nobody edits files in place.

Or let Nextflow handle it — it clones and caches automatically:

```bash
nextflow run <user>/ont16s -r v1.0.0 \
    -profile slurm,conda -params-file /shared/pipelines/site.yml \
    --step all --pod5_dir /project/run/pod5 --metadata metadata.tsv
```

Pinning `-r v1.0.0` means a colleague's run is reproducible even after you push
changes.

## 4. Smoke test before telling anyone

Cheapest first — compiles the script, submits nothing:

```bash
nextflow run main.nf --help
```

Then the no-GPU path, using a couple of FASTQ files from a previous run:

```bash
nextflow run main.nf \
    -profile slurm,conda -params-file conf/site.yml \
    --step from_fastq --fastq_dir test_in --subsample 5000 \
    --outdir smoke_test
```

Then the full path with `-profile test`, which caps basecalling at 20k reads:

```bash
nextflow run main.nf \
    -profile slurm,conda,test -params-file conf/site.yml \
    --step all --pod5_dir /project/run/pod5 --metadata metadata.tsv \
    --outdir full_test
```

## 5. What to tell your team

> Pipeline: `github.com/<user>/ont16s`, deployed at `/shared/pipelines/ont16s`.
>
> `module load Java/25.36`, then run inside `tmux` — Nextflow dies with your SSH
> session otherwise.
>
> **Read `docs/GOTCHAS.md` first.** Several documented failures report success
> while silently losing data.
>
> Keep POD5 on project storage. A run needs ~95 GB and personal scratch quotas
> are often 100 GB.
