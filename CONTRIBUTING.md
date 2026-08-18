# Cómo contribuir

> 🌐 **Español** (versión principal) · [English](CONTRIBUTING.en.md)

## Antes de cambiar main.nf o nextflow.config

Estos dos archivos tomaron una docena de iteraciones hasta funcionar con el
parser estricto de Nextflow. Antes de abrir un PR que los toque, confirma que
el script aún compila:

```bash
nextflow run main.nf --help
```

Luego corre la prueba real más barata, que no necesita GPU:

```bash
nextflow run main.nf \
    -profile slurm,conda -params-file conf/site.yml \
    --step from_fastq --fastq_dir <unos-pocos-fastqs> --subsample 5000 \
    --outdir smoke_test
```

`results/06_tables/` con TSV no vacíos significa que el cambio es seguro.

## Configuraciones que no hay que "ordenar"

Cada una existe por un fallo específico. `docs/GOTCHAS.md` registra el síntoma
de cada uno.

- `--no-trim` en `DORADO_BASECALL` — los barcodes deben sobrevivir hasta el demux
- `samtools quickcheck -u` tras el basecalling — Dorado puede salir con 0 tras una escritura truncada
- Recorrido con `find` del árbol de demux — la estructura es anidada e incluye un nivel `unknown`
- `stageInMode = 'symlink'` — copiar ~90 GB de POD5 excede las cuotas típicas de scratch
- Sin `PATH` en el bloque `env {}` — los exports de `env` corren después de `beforeScript` y lo sobrescribirían
- `--nodes=1` en el `clusterOptions` de GPU — VSC rechaza trabajos de GPU sin él
- 48 GB para `cpu_med` — el índice minimap2 de SILVA muere por OOM con 16 GB
- `asInt()` alrededor de los parámetros numéricos — los parámetros de CLI llegan como Strings

## Añadir una base de datos

Extiende `bin/setup_databases.sh` y documenta el requisito de memoria.
Cualquier base con más de ~1M de referencias necesita subir la asignación de
`cpu_med`.



