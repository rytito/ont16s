#!/usr/bin/env bash
#
# Descarga y construye las bases de datos de Emu.
# Ejecutar UNA VEZ en un nodo de login -- los nodos de cómputo a menudo no
# tienen internet.
#
#   bash bin/setup_databases.sh /ruta/a/databases [gtdb|silva|default|all]
#
set -euo pipefail

DBROOT="${1:?uso: setup_databases.sh <raiz_de_bases> [cual]}"
WHICH="${2:-all}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$DBROOT"
echo "==> Raíz de bases de datos: $DBROOT"
echo "    Usa almacenamiento de PROYECTO, no scratch: scratch purga archivos"
echo "    sin acceso por 30 días, y estas son costosas de reconstruir."
echo

command -v emu >/dev/null || { echo "ERROR: activa primero el entorno de emu" >&2; exit 1; }

# --------------------------------------------------------------- GTDB r226
# Taxonomía actual, basada en genomas, ~77k secuencias SSU representativas
# de especie. Solo procariotas: SIN referencias de cloroplastos ni
# mitocondrias. Los nombres provisionales como "JACDBZ01 sp036380955" marcan
# organismos con genomas pero sin nombre válidamente publicado -- eso es una
# característica, no un fallo.
if [[ "$WHICH" == "gtdb" || "$WHICH" == "all" ]] && [ ! -d "$DBROOT/emu_gtdb_r226" ]; then
    echo "==> GTDB r226"
    mkdir -p "$DBROOT/gtdb_r226" && cd "$DBROOT/gtdb_r226"

    BASE=https://data.gtdb.ecogenomic.org/releases/release226/226.0/genomic_files_reps
    echo "    Archivos SSU disponibles (ajusta los nombres si GTDB los movió):"
    curl -s "$BASE/" | grep -oE 'href="[^"]*ssu[^"]*"' || true

    # ssu_reps, NO ssu_all: ssu_all contiene todas las copias de SSU de
    # 732k genomas y haría a Emu imprácticamente lento.
    wget -nc "$BASE/bac120_ssu_reps_r226.fna.gz"
    wget -nc "$BASE/ar53_ssu_reps_r226.fna.gz"
    zcat bac120_ssu_reps_r226.fna.gz ar53_ssu_reps_r226.fna.gz > ssu_reps_r226.fna

    python3 "$SCRIPT_DIR/gtdb_to_emu.py" ssu_reps_r226.fna ./emu_input

    echo
    echo "    REVISA -- la especie debe ser un binomio:"
    head -2 emu_input/taxonomy.tsv | awk -F'\t' '{print "      ["$2"]"}'
    echo

    cd "$DBROOT"
    emu build-database emu_gtdb_r226 \
        --sequences     "$DBROOT/gtdb_r226/emu_input/sequences.fasta" \
        --seq2tax       "$DBROOT/gtdb_r226/emu_input/seq2tax.map" \
        --taxonomy-list "$DBROOT/gtdb_r226/emu_input/taxonomy.tsv"
fi

# --------------------------------------------------------------- SILVA
# La única de las tres que etiqueta Chloroplast y Mitochondria, así que es
# la que se usa para cuantificar contaminación de planta/hospedador. Las
# anotaciones de SILVA a nivel de especie se consideran poco fiables --
# úsala a nivel de género.
# NOTA: 2.2M de referencias; Emu necesita ~48 GB de RAM por tarea con ella.
if [[ "$WHICH" == "silva" || "$WHICH" == "all" ]] && [ ! -d "$DBROOT/emu_silva" ]; then
    echo "==> SILVA 138.2"
    pip install --quiet osfclient
    mkdir -p "$DBROOT/emu_silva" && cd "$DBROOT/emu_silva"
    echo "    Bases de datos preconstruidas disponibles:"
    osf -p 56uf7 ls | grep -i prebuilt || true
    osf -p 56uf7 fetch osfstorage/emu-prebuilt/silva-138.2.tar
    tar -xf silva-138.2.tar && rm silva-138.2.tar
fi

# --------------------------------------------------------------- Emu default
# rrnDB v5.6 + NCBI 16S RefSeq, congelada en septiembre de 2020. Anterior a
# la división de Lactobacillus (Zheng et al. 2020) y cubre mal los taxones
# ambientales no cultivados. Útil solo para comparar con literatura antigua.
if [[ "$WHICH" == "default" || "$WHICH" == "all" ]] && [ ! -d "$DBROOT/emu_default" ]; then
    echo "==> Emu por defecto (NCBI 16S, 2020)"
    pip install --quiet osfclient
    mkdir -p "$DBROOT/emu_default" && cd "$DBROOT/emu_default"
    osf -p 56uf7 fetch osfstorage/emu-prebuilt/emu.tar
    tar -xf emu.tar && rm emu.tar
fi

echo
echo "==> Listo. Verifica que cada base tenga species_taxid.fasta y taxonomy.tsv:"
find "$DBROOT" -maxdepth 2 -name "taxonomy.tsv" | sed 's/^/    /'
echo
echo "==> Luego define en conf/site.yml:"
echo "    emu_dbs: 'gtdb:$DBROOT/emu_gtdb_r226'"
