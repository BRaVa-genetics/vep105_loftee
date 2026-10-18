# VEP version 105 with LOFTEE v1.04_GRCh38 containers

*This repository is [part 1](https://github.com/BRaVa-genetics/variant-annotation#1-run-vep-105-with-loftee) of the full BRaVa annotation pipeline. Instructions for the full pipeline are [here](https://github.com/BRaVa-genetics/variant-annotation).*

Annotate your variant sites using VEP, ready for processing into SAIGE annotation group files.

> [!IMPORTANT]
> **Changes (October 2026)**
> 1. **dbNSFP 5.4a** (REVEL, CADD 1.7) instead of 4.3a, whose download link no longer works. dbNSFP 5 needs a free
>    academic registration; `download_data.sh` explains the one manual step.
> 2. **No LOFTEE conservation database (`conservation_file`).** With VEP's `--fork` it makes LOFTEE drop LoF calls at
>    random; HC/LC do not depend on it. See [Why no conservation database](#why-no-conservation-database).
>    `--fork` is now safe, and recommended.
> 3. **Check that LOFTEE never failed** (one `grep`, [below](#check-loftee)) before going on.
> 4. **Variant IDs are overwritten** with `CHROM:POS:REF:ALT` before VEP (previously only missing IDs were filled, and
>    the IDs were set on a file the later steps did not use), so the gnomAD popmax filter sees every variant.

### Contents

* [Requirements](#requirements)
* [Pre-processing](#pre-processing)
* [VEP annotation](#vep-annotation)
  * [VEP annotation using Docker](#vep-annotation-using-docker)
  * [VEP annotation using Singularity](#vep-annotation-using-singularity)
  * [Check LOFTEE](#check-loftee)
  * [Why no conservation database](#why-no-conservation-database)
* [Post-processing](#post-processing)

## Requirements

Required unix packages: `docker` (or Singularity/Apptainer), `tabix`/`bgzip` (htslib) and `bcftools`:

```
sudo apt-get install tabix bcftools
```

Instructions on [installing Docker available here](https://docs.docker.com/engine/install/ubuntu/).

## Pre-processing
Split multiallelic variants (including genotype data), set every variant ID to `CHROM:POS:REF:ALT`, and drop the
genotypes, so that VEP sees a sites-only VCF. The IDs matter: the gnomAD popmax filter in
[post-processing](#post-processing) matches on them, and a variant with any other ID (an rsID, or `.`) is silently
kept.
```
wget http://hgdownload.cse.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz
bcftools norm -m-any --check-ref w -f hg38.fa.gz input.vcf.gz -Ou \
  | bcftools annotate --set-id '%CHROM:%POS:%REF:%FIRST_ALT' -Ou \
  | bcftools view --drop-genotypes -O z -o sites_only_input_split_multiallelic.vcf.gz
```
## VEP annotation
Download all required resources into `vep_data/`. This takes a while: the files are large (~45 GB in the end).
```
bash download_data.sh
```
dbNSFP 5.4a needs a free academic registration at <https://www.dbnsfp.org/download>: download the academic
`dbNSFP5.4a.zip` (or `dbNSFP5.4a_grch38.gz`) into `vep_data/` and rerun `download_data.sh`, which cuts it to the
columns VEP needs.

Now you have the choice between using Docker or Singularity containers. In both, `--fork N` runs N VEP processes in
parallel (4 to 8 is reasonable); it is safe because LOFTEE no longer reads the conservation database.
### VEP annotation using Docker
Pull the docker image built from the Dockerfile in this repository:
```
docker pull ghcr.io/brava-genetics/vep105_loftee:main
```
VEP annotate your VCF files. Below is an example, annotating chromosome 21 in UK Biobank data. Go ahead and replace `vep_data/ukb_450k_wes/sites_only_input_split_multiallelic_chr${chr}.vcf.gz` and `out/sites_only_output_chr${chr}_vep.vcf` with the relevant input file and desired output filename, respectively, to annotate your sites only VCFs.
```
chr=21
cmd="vep -i vep_data/ukb_450k_wes/sites_only_input_split_multiallelic_chr${chr}.vcf.gz \
         --assembly GRCh38 \
         --vcf \
         --format vcf \
         --cache \
         --dir_cache vep_data \
         -o out/sites_only_output_chr${chr}_vep.vcf \
         --plugin LoF,loftee_path:/opt/micromamba/share/ensembl-vep-105.0-1,human_ancestor_fa:vep_data/human_ancestor.fa.gz,gerp_bigwig:vep_data/gerp_conservation_scores.homo_sapiens.GRCh38.bw \
         --plugin dbNSFP,vep_data/dbNSFP5.4a_brava.as_v4.txt.gz,REVEL_score,CADD_phred \
         --everything \
         --force_overwrite \
         --offline \
         --fork 4"

docker run -v $(pwd):/$HOME/ -w $HOME ghcr.io/brava-genetics/vep105_loftee:main $cmd
```
Note that in order for the docker container to "see" the files required for VEP annotation, you will need to mount the directory containing the required resources and the VCF to be annotated. This is what `-v $(pwd):/$HOME/` is doing. If your VCF file to be annotated is located somewhere else, you will also need to mount the directory that it sits in, or move it to the current working directory (or any subfolder within the working directory) if you're using the above code as a template.

### VEP annotation using Singularity
Pull docker image built from the Dockerfile in this repo and convert to a singularity.sif.
```
singularity pull --disable-cache "vep_data/vep.sif" "docker://ghcr.io/brava-genetics/vep105_loftee:main"
```
VEP annotate your VCF files, with the same `cmd` as for Docker above:
```
singularity exec --bind $(pwd):$HOME/ -W $HOME "vep_data/vep.sif" $cmd
```
As with docker, in order for our singularity container to "see" the files required for VEP annotation, you will need to mount the directory containing the required resources and the VCF to be annotated. This is what `--bind $(pwd):$HOME/` is doing.

### Check LOFTEE
LOFTEE reports its own failures in VEP's warnings file, and a variant it fails on gets no LoF call at all (a
stop_gained or frameshift that should be pLoF ends up as non_coding). This must print 0:
```
grep -c "Plugin 'LoF' went wrong" out/sites_only_output_chr${chr}_vep.vcf_warnings.txt
```
The annotation script in step 3 also refuses to write group files when a stop_gained / frameshift / splice donor or
acceptor entry has no LOFTEE call.

### Why no conservation database
LOFTEE's optional `conservation_file` (`loftee.sql`, PhyloCSF scores) is an SQLite database that LOFTEE opens once,
when the plugin starts. VEP's `--fork` then copies that open connection into every worker process; the workers share
one file handle, their reads interleave, SQLite reports `database disk image is malformed` or `file is not a
database`, and LOFTEE drops the LoF call of the variant it was working on. It happens at random, on roughly 0.4% of
stop_gained / frameshift variants, and it clusters: in the October 2026 BRaVa rebuild it removed 2,060 calls in 291
genes, including 96 in BRCA2 and 70 in TET2. The database only adds the `PHYLOCSF_WEAK` / `PHYLOCSF_UNLIKELY_ORF`
flags and `ANN_ORF` / `MAX_ORF` info, never a filter, so HC and LC calls do not depend on it. On 15,074 random All of
Us variants, VEP with `--fork 8` and no database agreed with All of Us' own LOFTEE calls on every one of 17,773
(variant, gene) rows; with the database it lost 3 HC calls.

## Post-processing

Now we need to determine the "worst consequence by gene on the MANE SELECT transcript (if available) or the 'canonical' transcript (if MANE SELECT isn't available)" variant annotations (wow, what a mouthful). To munge the data into a format to carry this out easily (with our python code in the [SAIGE_annotations directory of the variant-annotation repository](https://github.com/BRaVa-genetics/variant-annotation/tree/main/SAIGE_annotations), we use the BCFtools split-vep plugin). If you don't have BCFtools (we'd be surprised though), go ahead and install it following the instructions [here](https://samtools.github.io/bcftools/howtos/install.html). In order to use the BCFtools plugins, the environment variable `BCFTOOLS_PLUGINS` must be set and point to the correct location:

```
export BCFTOOLS_PLUGINS=/path/to/bcftools/plugins
```

(replacing `/path/to/bcftools/plugins` with the path to your BCFtools plugins folder). It may already be set within your compute environment, so make sure to check that first!

```
bgzip out/sites_only_output_chr${chr}_vep.vcf
tabix out/sites_only_output_chr${chr}_vep.vcf.gz
bcftools view -i'ID!=@vep_data/gnomad.exomes.r2.1.1.sites.liftover_grch38_popmax_0.01.tsv.bgz' out/sites_only_output_chr${chr}_vep.vcf.gz -o out/sites_only_output_chr${chr}_vep.gnomad_popmax_0.01.vcf.gz -O z

bcftools +split-vep out/sites_only_output_chr${chr}_vep.gnomad_popmax_0.01.vcf.gz -d -f '%CHROM:%POS:%REF:%ALT %Gene %LoF %REVEL_score %CADD_phred %Consequence %Feature %MANE_SELECT %CANONICAL %BIOTYPE\n' -o out/sites_only_output_chr${chr}_vep.gnomad_popmax_0.01_processed.txt
sed -i '1i SNP_ID GENE LOF REVEL_SCORE CADD_PHRED CSQ TRANSCRIPT MANE_SELECT CANONICAL BIOTYPE' out/sites_only_output_chr${chr}_vep.gnomad_popmax_0.01_processed.txt
```
The above commands exclude the set of variants in `vep_data/gnomad.exomes.r2.1.1.sites.liftover_grch38_popmax_0.01.tsv.bgz` (which are variants with a popmax > 0.01 in gnomAD v2), splits multiple transcript annotations for a given variant across multiple lines, grabs a subset of columns that we need to define our annotations for the SAIGE group files, and gives them some nice names.

We will also create a processed version of the VEP annotated files without the popMAX filter which will be useful for average allele count and variant count across annotations split by MAF and MAC (see instructions using this output to generate these summary files and plots [here](https://github.com/BRaVa-genetics/BRaVa_curation/tree/main/QC/annotation_summary))
```
bcftools +split-vep out/sites_only_output_chr${chr}_vep.vcf.gz -d -f '%CHROM:%POS:%REF:%ALT %Gene %LoF %REVEL_score %CADD_phred %Consequence %Feature %MANE_SELECT %CANONICAL %BIOTYPE\n' -o out/sites_only_output_chr${chr}_vep.processed.txt
sed -i '1i SNP_ID GENE LOF REVEL_SCORE CADD_PHRED CSQ TRANSCRIPT MANE_SELECT CANONICAL BIOTYPE' out/sites_only_output_chr${chr}_vep.processed.txt
```
