#!/usr/bin/env nextflow

/*
 * ont16s -- Pipeline de Oxford Nanopore para 16S rRNA de longitud completa
 *
 *   POD5 (sin basecalling) -> Dorado -> demux -> QC -> Emu -> phyloseq
 *
 * Escrito para la química Kit 14 (R10.4.1 / FLO-MIN114), SQK-16S114.24,
 * con el basecalling DESACTIVADO en el secuenciador.
 *
 * Requiere Nextflow >= 26.04 (sintaxis estricta). La selección de etapa usa
 * --step, no -entry, que el parser estricto eliminó.
 */

/* ------------------------------------------------------------------ *
 *  Texto de ayuda
 * ------------------------------------------------------------------ */

def helpMessage() {
    log.info """
    ========================================================================
     ont16s  v${workflow.manifest.version}
    ========================================================================

    Ejecución típica:

      nextflow run main.nf \\
          -profile slurm,conda \\
          -params-file conf/site.yml \\
          --step all \\
          --pod5_dir /ruta/a/la/corrida/pod5 \\
          --outdir results

    Etapas (--step, por defecto '${params.step}'):
      all         POD5 -> tablas de abundancia (+ phyloseq si se da --metadata)
      from_bam    --calls_bam <archivo>  omite el basecalling
      from_fastq  --fastq_dir <dir>      omite el basecalling y el demultiplexado

    Entradas:
      --pod5_dir      Directorio POD5. Con el basecalling desactivado MinKNOW
                      escribe 'pod5/', no 'pod5_pass/'.
      --calls_bam     BAM no alineado de un basecalling previo
      --fastq_dir     FASTQ por muestra (archivos llamados barcodeNN.fastq)
      --metadata      TSV con una columna SampleID; habilita la salida phyloseq
      --outdir        Directorio de salida [${params.outdir}]

    Basecalling:
      --model         Modelo de Dorado [${params.model}]
      --max_reads     Tope de lecturas (pruebas) [${params.max_reads ?: 'ninguno'}]

    Demultiplexado:
      --kit                  Kit de barcoding [${params.kit}]
      --barcode_both_ends    Exigir barcode en ambos extremos [${params.barcode_both_ends}]

    Filtrado y profundidad:
      --min_qscore    [${params.min_qscore}]
      --min_len       [${params.min_len}]
      --max_len       [${params.max_len}]
      --subsample     Lecturas por muestra, 0 = desactivado [${params.subsample}]
      --min_reads     Excluir muestras por debajo de esta profundidad [${params.min_reads}]

    Taxonomía:
      --emu_dbs       nombre:ruta[,nombre:ruta,...]

    Perfiles: slurm, vsc_wice, vsc_genius, conda, apptainer, test, debug

    Documentación completa: docs/USAGE.md (English: docs/USAGE.en.md)
    Lee docs/GOTCHAS.md antes de tu primera corrida real.
    """.stripIndent()
}

/* ------------------------------------------------------------------ *
 *  Funciones auxiliares
 * ------------------------------------------------------------------ */

// Los parámetros de la línea de comandos llegan como Strings; los de un
// config o params-file llegan tipados. Convierte antes de comparar números.
def asInt(v) {
    return v == null ? 0 : v.toString().toInteger()
}

// "gtdb:/ruta,silva:/ruta" -> canal de [nombre, ruta]
def parseDatabases(spec) {
    if( !spec )
        error "--emu_dbs es obligatorio, p. ej. --emu_dbs 'gtdb:/db/emu_gtdb_r226'"

    return Channel.from(spec.toString().split(','))
        .map { entry ->
            def bits = entry.trim().split(':')
            if( bits.size() != 2 )
                error "Entrada de --emu_dbs mal formada: '${entry}'. Se espera nombre:ruta"
            def dir = file(bits[1])
            if( !dir.exists() )
                error "Base de datos de Emu no encontrada: ${bits[1]}"
            tuple(bits[0], dir)
        }
}

// Dorado reconstruye el árbol de MinKNOW desde los metadatos del POD5:
//   <experiment>/<sample_id>/<run_id>/bam_pass/barcodeNN/*.bam
// sample_id suele ser literalmente "unknown". Nunca uses glob con ruta fija.
def barcodeOf(f) {
    def m = (f.toString() =~ /(barcode\d+|unclassified)/)
    return m ? m[0][1] : 'unknown'
}

/* ------------------------------------------------------------------ *
 *  Basecalling y demultiplexado
 * ------------------------------------------------------------------ */

process DORADO_BASECALL {
    label 'gpu'
    tag { pod5_dir.name }
    publishDir "${params.outdir}/01_basecall", mode: 'copy', pattern: '*.txt'

    input:
    path pod5_dir

    output:
    path 'calls.bam',    emit: bam
    path 'versions.txt', emit: versions

    script:
    def maxreads = params.max_reads ? "--max-reads ${params.max_reads}" : ''
    def bench    = params.batchsize_benchmarks ? "--batchsize-benchmarks-file ${params.batchsize_benchmarks}" : ''
    """
    nvidia-smi || { echo "ERROR: ninguna GPU visible en esta asignación" >&2; exit 1; }
    dorado --version > versions.txt 2>&1

    # --no-trim es esencial. Conserva los barcodes en las lecturas para que
    # dorado demux pueda encontrarlos. El basecalling con --kit-name solo
    # ETIQUETA las lecturas; no las separa en archivos por muestra.
    dorado basecaller ${params.model} ${pod5_dir} \\
        --no-trim \\
        --recursive \\
        --device cuda:all \\
        ${maxreads} ${bench} \\
        > calls.bam

    # Dorado puede salir con 0 tras una escritura truncada (la cuota de
    # disco es la causa habitual), así que verifica explícitamente. -u suprime
    # la advertencia "no targets in header", normal en BAM no alineado; solo
    # un bloque EOF ausente indica truncamiento real.
    samtools quickcheck -u -v calls.bam || {
        echo "ERROR: calls.bam está truncado -- revisa la cuota de disco" >&2
        exit 1
    }
    """
}

process DORADO_DEMUX {
    label 'cpu_high'
    publishDir "${params.outdir}/02_demux", mode: 'copy', pattern: '**summary*.txt'

    input:
    path bam

    output:
    path 'demux/**/*.bam',         emit: bams
    path 'demux/**summary*.txt',   emit: summary, optional: true

    script:
    def both = params.barcode_both_ends?.toString()?.toBoolean() ? '--barcode-both-ends' : ''
    """
    dorado demux ${bam} \\
        --output-dir demux \\
        --kit-name ${params.kit} \\
        ${both} \\
        --emit-summary \\
        --threads ${task.cpus}

    find demux -name '*.bam' | xargs -r samtools quickcheck -u -v
    echo "BAMs del demux verificados"
    """
}

process BAM_TO_FASTQ {
    label 'cpu_low'
    tag { barcode }

    input:
    tuple val(barcode), path(bams)

    output:
    tuple val(barcode), path("${barcode}.raw.fastq"), emit: fastq

    script:
    // -T '*' lleva las etiquetas de barcode y de corrida al campo de
    // comentario del FASTQ. Dorado advierte que FASTQ no puede preservarlo
    // todo, así que el BAM se conserva como forma de archivo y esta es una
    // conversión de conveniencia.
    """
    for f in ${bams}; do
        samtools fastq -T '*' \$f
    done > ${barcode}.raw.fastq
    """
}

/* ------------------------------------------------------------------ *
 *  QC de lecturas
 * ------------------------------------------------------------------ */

process CHOPPER_FILTER {
    label 'cpu_low'
    tag { barcode }
    publishDir "${params.outdir}/03_filtered", mode: 'copy'

    input:
    tuple val(barcode), path(fastq)

    output:
    tuple val(barcode), path("${barcode}.fastq"), emit: fastq

    script:
    // Los amplicones 27F/1492R tienen su pico en ~1450-1550 pb. La ventana
    // elimina lecturas truncadas y concatémeros sin ser restrictiva.
    """
    chopper -q ${params.min_qscore} \\
            --minlength ${params.min_len} \\
            --maxlength ${params.max_len} \\
            -i ${fastq} > ${barcode}.fastq
    """
}

process SUBSAMPLE {
    label 'cpu_low'
    tag { barcode }
    publishDir "${params.outdir}/04_subsampled", mode: 'copy'

    input:
    tuple val(barcode), path(fastq)

    output:
    tuple val(barcode), path("${barcode}.sub.fastq"), emit: fastq

    script:
    // Las abundancias relativas se estabilizan muy por debajo de 20k
    // lecturas, mientras que el tiempo de Emu escala con la profundidad: 90k
    // lecturas tomaron >20 min/muestra, 20k toma ~4. La semilla fija lo hace
    // reproducible.
    """
    seqkit sample -n ${params.subsample} -s ${params.seed} ${fastq} \\
        > ${barcode}.sub.fastq
    """
}

process READ_STATS {
    label 'cpu_low'
    publishDir "${params.outdir}/qc", mode: 'copy'

    input:
    path fastqs

    output:
    path 'read_stats.tsv'
    path 'reads_per_barcode.tsv'

    script:
    """
    seqkit stats -a -T ${fastqs} > read_stats.tsv

    printf "barcode\\treads\\n" > tmp.tsv
    for f in ${fastqs}; do
        bc=\$(basename \$f | sed 's/\\..*//')
        n=\$(( \$(wc -l < \$f) / 4 ))
        printf "%s\\t%s\\n" "\$bc" "\$n" >> tmp.tsv
    done
    ( head -1 tmp.tsv; tail -n +2 tmp.tsv | sort -k2,2nr ) > reads_per_barcode.tsv
    rm tmp.tsv
    """
}

/* ------------------------------------------------------------------ *
 *  Perfilado taxonómico
 * ------------------------------------------------------------------ */

process EMU_ABUNDANCE {
    label 'cpu_med'
    tag { "${db_name}|${barcode}" }
    publishDir { "${params.outdir}/05_emu/${db_name}" }, mode: 'copy'

    input:
    tuple val(barcode), path(fastq), val(db_name), path(db_dir)

    output:
    tuple val(db_name), path("${barcode}_rel-abundance.tsv"), emit: abundance

    script:
    // PYTHONNOUSERSITE evita que los paquetes de ~/.local eclipsen el entorno.
    """
    export PYTHONNOUSERSITE=1
    emu abundance ${fastq} \\
        --db ${db_dir} \\
        --type map-ont \\
        --keep-counts \\
        --threads ${task.cpus} \\
        --output-dir . \\
        --output-basename ${barcode}
    """
}

process EMU_COMBINE {
    label 'cpu_low'
    tag { db_name }
    publishDir "${params.outdir}/06_tables", mode: 'copy', saveAs: { fn -> "${db_name}_${fn}" }

    input:
    tuple val(db_name), path(tsvs)

    output:
    tuple val(db_name), path('emu-combined-*.tsv'), emit: tables

    script:
    """
    export PYTHONNOUSERSITE=1
    mkdir -p combine && cp ${tsvs} combine/

    for rank in species genus family; do
        emu combine-outputs combine \$rank || true
        emu combine-outputs combine \$rank --counts || true
    done

    cp combine/emu-combined-*.tsv .
    """
}

/* ------------------------------------------------------------------ *
 *  phyloseq
 * ------------------------------------------------------------------ */

process BUILD_PHYLOSEQ {
    label 'cpu_low'
    tag { db_name }
    publishDir { "${params.outdir}/07_phyloseq/${db_name}" }, mode: 'copy'

    input:
    tuple val(db_name), path(tables)
    path metadata

    output:
    path 'phyloseq.rds',   emit: rds
    path '*.tsv',          emit: tsv,  optional: true
    path '*.pdf',          emit: pdf,  optional: true
    path 'sessionInfo.txt', emit: info, optional: true

    script:
    """
    COUNTS=\$(ls *combined-species-counts.tsv 2>/dev/null | head -1)
    if [ -z "\$COUNTS" ]; then
        echo "ERROR: no se encontró la tabla de conteos por especie" >&2
        exit 1
    fi
    build_phyloseq.R "\$COUNTS" ${metadata} . ${params.min_reads}
    """
}

/* ------------------------------------------------------------------ *
 *  Sub-workflows
 * ------------------------------------------------------------------ */

workflow DEMUX {
    take:
    ch_bam

    main:
    DORADO_DEMUX(ch_bam)

    // Agrupa los BAM anidados por barcode. unclassified se conserva en
    // disco vía publishDir pero se excluye del análisis posterior.
    ch_grouped = DORADO_DEMUX.out.bams
        .flatten()
        .map { f -> tuple(barcodeOf(f), f) }
        .filter { bc, f -> bc != 'unclassified' && bc != 'unknown' }
        .groupTuple()

    BAM_TO_FASTQ(ch_grouped)
    CHOPPER_FILTER(BAM_TO_FASTQ.out.fastq)

    emit:
    fastq = CHOPPER_FILTER.out.fastq
}

workflow PROFILE {
    take:
    ch_fastq

    main:
    ch_in = asInt(params.subsample) > 0
          ? SUBSAMPLE(ch_fastq).fastq
          : ch_fastq

    READ_STATS(ch_in.map { bc, f -> f }.collect())

    EMU_ABUNDANCE(ch_in.combine(parseDatabases(params.emu_dbs)))
    EMU_COMBINE(EMU_ABUNDANCE.out.abundance.groupTuple())

    if( params.metadata ) {
        BUILD_PHYLOSEQ(
            EMU_COMBINE.out.tables,
            file(params.metadata, checkIfExists: true)
        )
    }

    emit:
    tables = EMU_COMBINE.out.tables
}

/* ------------------------------------------------------------------ *
 *  Punto de entrada
 * ------------------------------------------------------------------ */

workflow {
    main:

    if( params.help ) {
        helpMessage()
    }
    else if( params.step == 'all' ) {
        if( !params.pod5_dir )
            error "--pod5_dir es obligatorio para --step all"
        ch_pod5 = Channel.fromPath(params.pod5_dir, type: 'dir', checkIfExists: true)
        DORADO_BASECALL(ch_pod5)
        DEMUX(DORADO_BASECALL.out.bam)
        PROFILE(DEMUX.out.fastq)
    }
    else if( params.step == 'from_bam' ) {
        if( !params.calls_bam )
            error "--calls_bam es obligatorio para --step from_bam"
        ch_bam = Channel.fromPath(params.calls_bam, checkIfExists: true)
        DEMUX(ch_bam)
        PROFILE(DEMUX.out.fastq)
    }
    else if( params.step == 'from_fastq' ) {
        if( !params.fastq_dir )
            error "--fastq_dir es obligatorio para --step from_fastq"
        ch_fastq = Channel
            .fromPath("${params.fastq_dir}/*.{fastq,fq,fastq.gz,fq.gz}", checkIfExists: true)
            .map { f -> tuple(f.simpleName, f) }
        PROFILE(ch_fastq)
    }
    else {
        error "Valor de --step desconocido: '${params.step}'. Usa all | from_bam | from_fastq"
    }
}
