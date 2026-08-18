# Uso

> 🌐 **Español** (versión principal) · [English](USAGE.en.md)

## Configuración inicial del sitio (una sola vez)

### Java y Nextflow

Java no está en el `PATH` por defecto en la mayoría de clústeres, y los módulos
cargados no persisten entre sesiones:

```bash
module spider Java
module load Java/25.36        # usa lo que reporte module spider
java -version
```

Luego Nextflow:

```bash
mkdir -p ~/software && cd ~/software
curl -s https://get.nextflow.io | bash
./nextflow -version           # requiere >= 26.04
```

Más limpio para un grupo compartido, porque incluye su propio JRE y fija la
versión del motor para todos:

```bash
micromamba create -y -p /shared/conda_envs/nextflow -c conda-forge -c bioconda nextflow
```

Fija la versión en cualquier caso — Nextflow 26.04 introdujo cambios de
sintaxis incompatibles, y la próxima versión puede hacerlo también:

```bash
export NXF_VER=26.04.6
```

### Dorado

Dorado se distribuye como un tarball autocontenido con su propio runtime CUDA,
lo que lo convierte en la opción más robusta en un clúster compartido: sin
conflictos de módulos, sin passthrough de GPU en contenedores.

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

Descarga el modelo **en un nodo de login**. Los nodos de cómputo pueden no
tener internet, y un trabajo de GPU que muere a los veinte minutos porque no
pudo descargar un modelo es asignación desperdiciada.

**Coloca Dorado y sus modelos en el almacenamiento del grupo.** Un directorio
personal (home o data) significa que el pipeline se rompe para todos los demás
cuando una cuenta cambia.

#### Por qué `sup@v5.2.0`

Dorado 2.x introdujo `hac@v6.0.0` para R10.4.1, pero ONT no publicó ningún
modelo **SUP** v6 para esta química. `sup@v5.2.0` sigue siendo el más preciso
disponible, y la precisión importa para la asignación de 16S a nivel de
especie.

### Entornos y bases de datos

```bash
bash bin/setup_environments.sh /shared/conda_envs
micromamba activate /shared/conda_envs/emu
bash bin/setup_databases.sh /shared/databases gtdb
```

`setup_environments.sh` instala `pod5` y `NanoPlot` vía pip deliberadamente: la
receta de bioconda para `pod5` fija `polars >=0.19,<1.dev0`, que ya no resuelve
contra Python moderno y rompe todo el solve.

### Entorno del shell

```bash
cat >> ~/.bashrc <<'EOF'
export NXF_HOME="$SCRATCH/.nextflow"
export NXF_WORK="$SCRATCH/nxf_work"
export APPTAINER_CACHEDIR="$SCRATCH/.apptainer/cache"
export APPTAINER_TMPDIR="$SCRATCH/.apptainer/tmp"
EOF
```

Las imágenes de contenedores y el directorio `work/` de Nextflow ocupan varios
GB. Sin estas variables terminan en tu directorio home y agotan su cuota.

## Planificación de almacenamiento

Una corrida completa de 16S en MinION necesita aproximadamente:

| Elemento | Tamaño |
|---|---|
| POD5 de entrada | ~85 GB |
| `calls.bam` | ~6 GB |
| Salida del demux | ~3 GB |
| `work/` de Nextflow | 2–3× los intermedios |

**Mantén los POD5 en el almacenamiento del proyecto** y apunta `--pod5_dir`
hacia allí. El pipeline establece `stageInMode = 'symlink'` para que Nextflow
no los duplique dentro de `work/`, pero las salidas publicadas igualmente
necesitan espacio. Revisa tu cuota antes de enviar los trabajos — excederla
trunca los BAM mientras Dorado sigue reportando éxito.

## Parámetros

### Entrada

| Parámetro | Por defecto | Notas |
|---|---|---|
| `--step` | `all` | `all` \| `from_bam` \| `from_fastq` |
| `--pod5_dir` | — | Con basecalling desactivado, MinKNOW escribe `pod5/`, no `pod5_pass/` |
| `--calls_bam` | — | Para `--step from_bam` |
| `--fastq_dir` | — | Para `--step from_fastq`; archivos llamados `barcodeNN.fastq` |
| `--metadata` | — | TSV con `SampleID`; habilita la salida phyloseq |
| `--outdir` | `results` | |

### Basecalling

| Parámetro | Por defecto | Notas |
|---|---|---|
| `--model` | `sup` | Se resuelve al mejor modelo para la química |
| `--max_reads` | ninguno | Tope para pruebas |
| `--batchsize_benchmarks` | ninguno | Archivo de batch-size en caché; ahorra ~15 s por trabajo |

### Demultiplexado

| Parámetro | Por defecto |
|---|---|
| `--kit` | `SQK-16S114-24` (guiones, no los puntos del nombre comercial de ONT) |
| `--barcode_both_ends` | `true` |

En este kit los barcodes van sobre los primers 27F/1492R, así que **ambos
extremos de cada amplicón llevan uno**. Exigir concordancia suprime el index
hopping, que de otro modo aparece como taxones fantasma que se filtran entre
muestras. A cambio, espera un 5–15% de lecturas en `unclassified` — vale la
pena para cualquier estudio comparativo. Ponlo en `false` solo si
`unclassified` supera ~25%, lo que sugiere extremos de amplicón degradados.

### Filtrado y profundidad

| Parámetro | Por defecto | Notas |
|---|---|---|
| `--min_qscore` | `10` | |
| `--min_len` / `--max_len` | `1200` / `1800` | Los amplicones 27F/1492R tienen su pico en 1450–1550 pb |
| `--subsample` | `20000` | `0` lo desactiva |
| `--seed` | `42` | Submuestreo reproducible |
| `--min_reads` | `5000` | Las muestras por debajo se excluyen del objeto phyloseq |

El submuestreo es la mayor palanca sobre el tiempo de ejecución. Emu escala con
la profundidad: a 90k lecturas por muestra tardó más de 20 minutos cada una, a
20k unos cuatro. Las abundancias relativas son estables muy por debajo de 20k,
así que no se pierde nada significativo.

### Taxonomía

| Parámetro | Notas |
|---|---|
| `--emu_dbs` | `nombre:ruta[,nombre:ruta,...]` — perfila contra cada una en secuencia |

| Base de datos | Úsala para | No la uses para |
|---|---|---|
| **GTDB r226** | Taxonomía principal. Nombres actuales, basada en genomas, placeholders honestos | Detección de cloroplastos/mitocondrias — solo procariotas |
| **SILVA 138.2** | Cuantificar contaminación de planta/hospedador (etiqueta Chloroplast, Mitochondria) | Asignaciones a nivel de especie — ampliamente consideradas poco fiables |
| **Emu por defecto** | Comparación con literatura antigua | Cualquier cosa actual. Congelada en sept. 2020 |

Ejecutar dos bases de datos es una medida de confianza barata: un género con
abundancia similar en ambas es una asignación sólida; uno al 30% en una y al 2%
en la otra es un artefacto de base de datos. Pero SILVA necesita ~48 GB de RAM
por tarea y aproximadamente triplica el tiempo de ejecución, así que GTDB sola
es el valor por defecto sensato para el trabajo rutinario.

## Perfiles

Se combinan con comas: `-profile vsc_wice,conda`

| Perfil | Propósito |
|---|---|
| `standard` | Ejecución local |
| `slurm` | SLURM genérico; define `--partition_cpu`, `--partition_gpu`, `--account` |
| `vsc_wice` | KU Leuven wICE: `gpu_h100` + `batch_sapphirerapids` |
| `vsc_genius` | KU Leuven Genius: `gpu_v100` (techo de 4 cores/GPU) |
| `conda` | Entornos conda preconstruidos |
| `apptainer` | Contenedores para todo excepto Dorado |
| `test` | `--max_reads 20000 --subsample 5000 --min_reads 100` |
| `debug` | Imprime hostname, `nvidia-smi` y `PATH` antes de cada tarea |

### Techos por partición

Exceder el límite de cores por GPU hace que el trabajo sea rechazado de plano.

| Clúster | Partición | Máx. cores/GPU | Máx. mem/GPU |
|---|---|---|---|
| wICE | `gpu_h100` | 16 | 187200 MiB |
| wICE | `gpu_a100` | 18 | 126000 MiB |
| Genius | `gpu_v100` | 4 | 84000 MiB |
| Genius | `gpu_p100` | **inutilizable** | Dorado no soporta P100/GP100 |

### Por qué Dorado no va en contenedor

El passthrough de GPU necesita `--nv`, las versiones de driver del host y de la
imagen deben ser compatibles, y el binario estático ya incluye su runtime CUDA.
Ponerlo en contenedor añade modos de fallo sin ganancia alguna. Define
`--dorado_bin` en su lugar.

Si tu sitio exige contenedorización completa, añade
`apptainer.runOptions = '--nv'`, provee una imagen de Dorado de ONT, y prueba
primero la visibilidad de la GPU con `-profile debug`.

## Tiempos de ejecución medidos

Una H100, 24 barcodes, 2.4M de lecturas desde ~86 GB de POD5:

| Etapa | Tiempo |
|---|---|
| Basecalling `sup@v5.2.0` | ~1 h (2.8e7 muestras/s, 54 GB de RSS pico) |
| Demultiplexado (16 cores) | ~8 min |
| Emu por muestra, 20k lecturas, GTDB | ~4 min |
| Emu por muestra, 20k lecturas, SILVA | ~10 min, necesita 48 GB |

Las tareas de Emu corren en paralelo, así que 24 muestras contra GTDB terminan
aproximadamente en el tiempo de un par de muestras si hay nodos libres.

## Ejecución segura

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

Desacopla con **Ctrl+B** y luego **D**; vuelve con `tmux attach -t ont16s`.

**No** uses Ctrl+Z sobre un pipeline en ejecución — suspende el proceso y deja
retenido el lock de sesión, lo que después bloquea `-resume`. Usa Ctrl+C una
vez en su lugar; Nextflow cancela limpiamente y libera el lock.

Monitoreo desde otro shell:

```bash
squeue -M wice -u $USER
ls results/                      # los directorios aparecen en orden de etapa
tail -20 .nextflow.log
```

`results/07_phyloseq/` (o `06_tables/` sin metadatos) significa que terminó.

## Reanudación

```bash
nextflow run main.nf ... -resume
```

Las tareas completadas quedan en caché y no se repiten. Tras un basecalling
exitoso y un fallo posterior,
`--step from_bam --calls_bam results/01_basecall/calls.bam` omite por completo
la etapa de GPU.
