# Publicación en GitHub

> 🌐 **Español** (versión principal) · [English](SETUP_GITHUB.en.md)

## 1. Crear el repositorio localmente

```bash
cd ont16s
git init
git add .
git commit -m "ont16s v1.0.0: ONT 16S pipeline, POD5 to phyloseq"
git branch -M main
```

`conf/site.yml` está en el gitignore — solo se versiona `site.yml.example`, ya
que el archivo real contiene rutas absolutas y un nombre de cuenta específicos
de un clúster.

## 2. Subir

```bash
gh repo create ont16s --public --source=. --push
```

O después de crearlo en la interfaz web:

```bash
git remote add origin git@github.com:<user>/ont16s.git
git push -u origin main
git tag -a v1.0.0 -m "First validated release"
git push --tags
```

## 3. Desplegar en un clúster como clon, no como copia

Esta es la parte que vale la pena hacer bien. Si la copia del clúster y el
repositorio son independientes, divergen y terminas sin saber cuál es la
autoritativa.

```bash
cd /shared/pipelines
git clone https://github.com/<user>/ont16s.git
cd ont16s
cp conf/site.yml.example conf/site.yml
$EDITOR conf/site.yml
```

Las actualizaciones llegan entonces con `git pull`, y nadie edita archivos en
el lugar.

O deja que Nextflow lo maneje — clona y cachea automáticamente:

```bash
nextflow run <user>/ont16s -r v1.0.0 \
    -profile slurm,conda -params-file /shared/pipelines/site.yml \
    --step all --pod5_dir /project/run/pod5 --metadata metadata.tsv
```

Fijar `-r v1.0.0` hace que la corrida de un colega sea reproducible incluso
después de que subas cambios.

## 4. Prueba de humo antes de avisar a nadie

Lo más barato primero — compila el script, no envía nada:

```bash
nextflow run main.nf --help
```

Luego la ruta sin GPU, usando un par de archivos FASTQ de una corrida anterior:

```bash
nextflow run main.nf \
    -profile slurm,conda -params-file conf/site.yml \
    --step from_fastq --fastq_dir test_in --subsample 5000 \
    --outdir smoke_test
```

Luego la ruta completa con `-profile test`, que limita el basecalling a 20k
lecturas:

```bash
nextflow run main.nf \
    -profile slurm,conda,test -params-file conf/site.yml \
    --step all --pod5_dir /project/run/pod5 --metadata metadata.tsv \
    --outdir full_test
```

## 5. Qué decirle a tu equipo

> Pipeline: `github.com/<user>/ont16s`, desplegado en `/shared/pipelines/ont16s`.
>
> `module load Java/25.36`, y luego correr dentro de `tmux` — de lo contrario
> Nextflow muere con tu sesión SSH.
>
> **Lean `docs/GOTCHAS.md` primero.** Varios de los fallos documentados
> reportan éxito mientras pierden datos silenciosamente.
>
> Mantengan los POD5 en el almacenamiento del proyecto. Una corrida necesita
> ~95 GB y las cuotas personales de scratch suelen ser de 100 GB.
