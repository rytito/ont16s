# Registro de cambios

> 🌐 **Español** (versión principal) · [English](CHANGELOG.en.md)

## 1.0.0

Primera versión. Validada de extremo a extremo en wICE (KU Leuven) con datos
reales de SQK-16S114.24: 24 barcodes, 2.4M de lecturas, ~86 GB de POD5.

### Validado

- `--step all` — basecalling con Dorado en `gpu_h100` hasta las tablas combinadas
- `--step from_fastq` — submuestreo, QC, perfilado con Emu multi-base de datos
- GTDB r226 (construida a medida) y SILVA 138.2 en la misma corrida
- Envío a SLURM, etiquetas de recursos, reintento con más memoria ante OOM
- Generación del objeto phyloseq con filtrado por profundidad y PERMANOVA

### Medido

| Etapa | Escala | Tiempo |
|---|---|---|
| Basecalling `sup@v5.2.0` | 2.4M lecturas, 1× H100 | ~1 h (2.8e7 muestras/s, 54 GB de RSS pico) |
| Demultiplexado | 2.4M lecturas, 16 cores | ~8 min |
| Emu, GTDB | 20k lecturas/muestra | ~4 min/muestra |
| Emu, SILVA | 20k lecturas/muestra | ~10 min/muestra, 48 GB |

### Compatibilidad

Requiere **Nextflow ≥ 26.04**, a cuya sintaxis estricta apunta: `--step` en
lugar de `-entry`, `error` en lugar de `exit`, `if`/`else if` en lugar de
`switch`, sin `workflow.onComplete`, y closures alrededor de las expresiones de
`publishDir` que referencian variables de entrada.

Fija el motor para reproducibilidad:

```bash
export NXF_VER=26.04.6
```

### Limitaciones conocidas

- Sin validación con `nf-schema`; los parámetros numéricos se convierten manualmente con `asInt()`
- Dorado no va en contenedor — define `--dorado_bin`
- Las lecturas `unclassified` se publican pero no se perfilan
- Sin resumen de MultiQC
