# ont16s

> 🌐 **Español** (versión principal) · [English](README.en.md)

Pipeline de Nextflow para secuenciación Oxford Nanopore del gen 16S rRNA de
longitud completa: desde la señal cruda en POD5 hasta un objeto `phyloseq`, en
un solo comando.

Construido y validado para la **química Kit 14** (R10.4.1 / FLO-MIN114) con el
**16S Barcoding Kit 24 V14 (SQK-16S114.24)**, con el basecalling **desactivado**
en el secuenciador y ejecutado en un clúster HPC.

```
POD5  ──▶  Dorado basecall      (GPU, sup@v5.2.0, --no-trim)
      ──▶  Dorado demux         (según kit, --barcode-both-ends)
      ──▶  samtools fastq       (conserva las etiquetas de barcode)
      ──▶  chopper              (q≥10, 1200–1800 pb)
      ──▶  seqkit sample        (normalización de profundidad)
      ──▶  Emu abundance        (una pasada por base de datos)
      ──▶  Emu combine          (tablas taxones × muestras)
      ──▶  phyloseq             (.rds + tablas de QC + gráficos)
```

## Por qué este pipeline y no wf-16s

El `wf-16s` de ONT es un buen workflow con un reporte HTML más vistoso. Este
pipeline difiere en tres aspectos que importan para uso en investigación:

- **Emu en lugar de Kraken2.** Emu resuelve las lecturas ambiguas mediante
  expectation-maximisation sobre alineamientos de longitud completa. El propio
  benchmarking de ONT con comunidades mock encontró que Kraken2 producía una
  cantidad sustancial de taxones falsos positivos donde los métodos basados en
  alineamiento no lo hacían.
- **Cualquier base de datos de referencia.** Incluye un conversor para
  **GTDB r226**, que corrige nombres de género obsoletos (*Lactobacillus* →
  *Lacticaseibacillus*, etc.) y asigna nombres provisionales honestos a los
  organismos no cultivados, en lugar de forzarlos hacia parientes nominales
  lejanos.
- **TSV planos y un objeto phyloseq**, no un reporte del que haya que extraer
  los datos a mano.

Ejecutar ambos y compararlos es una estrategia razonable: la concordancia entre
un método basado en EM y uno basado en k-mers, sobre conjuntos de referencia
distintos, es evidencia sólida; la discordancia señala exactamente los taxones
que no deberían ir en una figura.

## Inicio rápido

```bash
# 1. Entornos y bases de datos (una vez por sitio)
bash bin/setup_environments.sh /shared/conda_envs
micromamba activate /shared/conda_envs/emu
bash bin/setup_databases.sh /shared/databases gtdb

# 2. Configuración del sitio
cp conf/site.yml.example conf/site.yml
$EDITOR conf/site.yml          # rutas, cuenta, bases de datos

# 3. Ejecutar
nextflow run main.nf \
    -profile slurm,conda \
    -params-file conf/site.yml \
    --step all \
    --pod5_dir /project/myrun/pod5 \
    --metadata metadata.tsv \
    --outdir results
```

**Ejecútalo dentro de `tmux`.** Nextflow corre en primer plano y muere junto
con tu sesión SSH — `-resume` recupera lo completado, pero se pierde la etapa
en curso.

```bash
tmux new -s ont16s
# ... lanzar el pipeline ...
# Ctrl+B y luego D para desacoplar; tmux attach -t ont16s para volver
```

## Etapas

Se seleccionan con `--step`. La sintaxis estricta de Nextflow 26.04 eliminó
`-entry`.

| Punto de partida | Comando |
|---|---|
| POD5 (corrida completa) | `--step all --pod5_dir <dir>` |
| Un `calls.bam` existente | `--step from_bam --calls_bam calls.bam` |
| FASTQ por muestra | `--step from_fastq --fastq_dir <dir>` |

`from_bam` es lo que necesitas tras un fallo de demultiplexado o de perfilado —
omite por completo la etapa costosa de GPU.

## Salidas

```
results/
├── 01_basecall/        versiones de las herramientas
├── 02_demux/           resumen de barcoding
├── 03_filtered/        FASTQ por barcode, filtrado por calidad/longitud
├── 04_subsampled/      FASTQ con profundidad normalizada
├── 05_emu/<db>/        tablas de abundancia por muestra
├── 06_tables/          <db>_emu-combined-{species,genus,family}[-counts].tsv
├── 07_phyloseq/<db>/   phyloseq.rds, diversidad alfa, ordenación, gráficos
├── qc/                 estadísticas de lecturas, lecturas por barcode
└── pipeline_info/      timeline, reporte, trace, DAG
```

El objeto se carga directamente:

```r
ps <- readRDS("results/07_phyloseq/gtdb/phyloseq.rds")
```

## Metadatos

Un TSV con una columna `SampleID` que coincida con los nombres de los barcodes.
Ver `assets/metadata_template.tsv`. Cualquier otra columna se convierte en
variable de muestra, y las categóricas se prueban automáticamente con PERMANOVA.

```tsv
SampleID	sample_name	group	replicate
barcode01	S01	control	1
barcode02	S02	treatment	1
```

Sin `--metadata` el pipeline se detiene después de `06_tables`.

## Requisitos

- Nextflow **≥ 26.04** y Java 11+ (`module load Java/...` en la mayoría de
  clústeres)
- Una GPU NVIDIA con tensor cores. **Dorado no soporta P100/GP100.**
- Dorado ≥ 2.0 (binario estático; deliberadamente sin contenedor)
- conda/micromamba, o Apptainer

## Documentación

- [`docs/USAGE.md`](docs/USAGE.md) — parámetros, perfiles, configuración del
  clúster, tiempos de ejecución
- [`docs/GOTCHAS.md`](docs/GOTCHAS.md) — modos de fallo que encontramos, y cómo
  detectarlos

**Lee `GOTCHAS.md` antes de tu primera corrida real.** Varios de los fallos
documentados reportan éxito mientras pierden datos silenciosamente.

## Cómo citar

Cita las herramientas subyacentes: Dorado (Oxford Nanopore), Emu (Curry *et al.*
2022, *Nature Methods*), minimap2 (Li 2018), chopper/nanoq, seqkit, phyloseq
(McMurdie & Holmes 2013), más tu base de datos de referencia **con su número de
versión** — GTDB r226, SILVA 138.2 o NCBI 16S RefSeq. La taxonomía difiere
sustancialmente entre ellas, así que la versión importa.

Si reportas resultados de GTDB, indica en tus métodos que los sufijos de género
como `Clostridium_S` y `Clostridium_B` denotan géneros distintos, separados a
partir de un género NCBI polifilético. Los revisores que no conocen GTDB los
leen como erratas.

## Financiamiento y créditos

Este pipeline fue desarrollado dentro del proyecto **MicroAndes** —
*Aprovechar los microbios para fortalecer a las comunidades andinas de
microproductores de alimentos fermentados* — una **Short Initiative de
VLIR-UOS** (proyecto KU Leuven
[3M250529](https://research.kuleuven.be/portal/nl/project/3M250529),
referencia de financiamiento PE2025SIN468A101, 2025–2027).

- **Institución coordinadora:** KU Leuven — Laboratorio de Bacteriología
  Molecular, Instituto Rega 
- **Instituciones socias:** Universidad Nacional del Centro del Perú (UNCP) y
  comunidades andinas de microproductores
- **Financiamiento:** VLIR-UOS (Vlaamse Interuniversitaire Raad), programa
  Short Initiatives

## Licencia

MIT — ver [`LICENSE`](LICENSE).
