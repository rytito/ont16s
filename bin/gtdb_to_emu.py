#!/usr/bin/env python3
"""
Convierte el FASTA ssu_reps de GTDB en las entradas de Emu build-database.

    gtdb_to_emu.py <ssu_reps.fna[.gz]> <directorio_salida>

Formato de encabezado de GTDB:

    >RS_GCF_000566285.1 d__Bacteria;p__Bacteroidota;...;s__Flavobacterium fluviatile [ssu_len=1510]

CRÍTICO: el linaje NO debe extraerse dividiendo el encabezado por espacios.
Los nombres de especie de GTDB son binomios que contienen un espacio, así que
un split ingenuo trunca 's__Flavobacterium fluviatile' a 'Flavobacterium' y
colapsa todas las especies de un género en un solo taxón. El síntoma es
muchos menos taxones únicos que secuencias (vimos 20,910 de 75,602). Este
script toma en cambio todo desde 'd__' hasta el primer campo de metadatos
entre corchetes.
"""

import gzip
import sys
from pathlib import Path

PREFIX = {
    "d__": "superkingdom", "p__": "phylum", "c__": "class",
    "o__": "order", "f__": "family", "g__": "genus", "s__": "species",
}
COLS = ["species", "genus", "family", "order", "class", "phylum", "superkingdom"]


def opener(path):
    return gzip.open(path, "rt") if str(path).endswith(".gz") else open(path, "rt")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)

    fasta_in = sys.argv[1]
    outdir = Path(sys.argv[2])
    outdir.mkdir(parents=True, exist_ok=True)

    lineage2taxid, taxid_rows, seq2tax, seen = {}, {}, [], {}
    next_taxid = 1
    n_seq = n_skip = 0

    with opener(fasta_in) as fh, open(outdir / "sequences.fasta", "w") as fo:
        keep = False
        for line in fh:
            if not line.startswith(">"):
                if keep:
                    fo.write(line)
                continue

            header = line[1:].rstrip()
            seq_id = header.split(None, 1)[0]

            i = header.find("d__")
            if i == -1:
                keep = False
                n_skip += 1
                continue

            rest = header[i:]
            b = rest.find(" [")
            lineage = (rest[:b] if b != -1 else rest).strip()

            ranks = {}
            for field in lineage.split(";"):
                field = field.strip()
                if field[:3] in PREFIX:
                    ranks[PREFIX[field[:3]]] = field[3:].strip()

            if not ranks.get("species"):
                keep = False
                n_skip += 1
                continue

            if lineage not in lineage2taxid:
                lineage2taxid[lineage] = next_taxid
                taxid_rows[next_taxid] = [ranks.get(c, "") for c in COLS]
                next_taxid += 1

            # Un genoma puede llevar varias copias de SSU bajo una misma accesión
            if seq_id in seen:
                seen[seq_id] += 1
                seq_id = f"{seq_id}_{seen[seq_id]}"
            else:
                seen[seq_id] = 0

            seq2tax.append((seq_id, lineage2taxid[lineage]))
            fo.write(f">{seq_id}\n")
            keep = True
            n_seq += 1

    with open(outdir / "seq2tax.map", "w") as f:
        for s, t in seq2tax:
            f.write(f"{s}\t{t}\n")

    with open(outdir / "taxonomy.tsv", "w") as f:
        f.write("tax_id\t" + "\t".join(COLS) + "\n")
        for tid in sorted(taxid_rows):
            f.write(str(tid) + "\t" + "\t".join(taxid_rows[tid]) + "\n")

    print(f"secuencias escritas: {n_seq}")
    print(f"taxones únicos:      {len(lineage2taxid)}")
    print(f"omitidas:            {n_skip}")
    print()
    print("VERIFICA -- la columna de especie debe ser un binomio (dos palabras):")
    print(f"  head -2 {outdir / 'taxonomy.tsv'} | awk -F'\\t' '{{print $2}}'")
    print("  se espera 'Flavobacterium fluviatile', NO 'Flavobacterium'")
    print()
    print("No uses `column -t` para inspeccionarlo: divide por cualquier")
    print("espacio en blanco y hace que cada rango parezca desplazado en uno.")


if __name__ == "__main__":
    main()
