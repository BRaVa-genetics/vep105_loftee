# VEP version 105 with LOFTEE v1.04_GRCh38 containers

*This repository is [part 1](https://github.com/BRaVa-genetics/variant-annotation#1-run-vep-version-105-with-loftee-v104_grch38) of the full BRaVa annotation pipeline. Instructions for the full pipeline are [here](https://github.com/BRaVa-genetics/variant-annotation).*

Annotate your variant sites using VEP, ready for processing into SAIGE annotation group files.

### Contents

* [Requirements](#requirements)
* [Pre-processing](#pre-processing)
* [VEP annotatation](#vep-annotatation)
  * [VEP annotation using Docker](#vep-annotation-using-docker)
  * [VEP annotation using Singularity](#vep-annotation-using-singularity)
* [Post-processing](#post-processing)

## Requirements

Required unix packages: `docker`, `tabix` and `bcftools` can be installed with:

```
sudo apt-get install tabix bcftools
```

Instructions on [installing Docker available here](https://docs.docker.com/engine/install/ubuntu/).

## Pre-processing
Before starting, ensure that the VCF has split multiallelic variants. If it has not, you will need to split-multiallelics in the VCF (including genotype data):
```
wget http://hgdownload.cse.ucsc.edu/goldenPath/hg38/bigZips/hg38.fa.gz -P
bcftools norm -m-any --check-ref w -f hg38.fa.gz input.vcf.gz -o input_split_multiallelic.vcf.gz -O z
```
Also, ensure that the variant IDs are defined by `CHROM:POS:REF:ALT` in the sites only VCFs (if not, then the gnomAD variants with popmax AF > 0.01 will not be excluded!)
```
bcftools annotate --set-id +'%CHROM:%POS:%REF:%FIRST_ALT' input_split_multiallelic.vcf.gz -o input_split_multiallelic_renamed.vcf.gz -O z
```
Finally, ensure that the VCF file that you pass to VEP is a sites only VCF with the genotype data removed:
```
bcftools view --drop-genotypes input_split_multiallelic.vcf.gz -O z -o sites_only_input_split_multiallelic.vcf.gz
```
## VEP annotation
Download all required resources into vep_data/. This might take a while, are these files are quite large (many GB)!
```
bash download_data.sh
```
Now you have the choice between using Docker or Singularity containers. 
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
         --plugin LoF,loftee_path:/opt/micromamba/share/ensembl-vep-105.0-1,human_ancestor_fa:vep_data/human_ancestor.fa.gz,conservation_file:vep_data/loftee.sql,gerp_bigwig:vep_data/gerp_conservation_scores.homo_sapiens.GRCh38.bw \
         --plugin dbNSFP,vep_data/dbNSFP4.3a.txt.gz,REVEL_score,CADD_phred \
         --everything \
         --force_overwrite \
         --offline"

docker run -v $(pwd):/$HOME/ -w $HOME -it ghcr.io/brava-genetics/vep105_loftee:main $cmd
```
Note that in order for the docker container to "see" the files required for VEP annotation, you will need to mount the directory containing the required resources and the VCF to be annotated. This is what `-v $(pwd):/$HOME/` is doing. If your VCF file to be annotated is located somewhere else, you will also need to mount the directory that it sits in, or move it to the current working directory (or any subfolder within the working directory) if you're using the above code as a template. `-it` runs our vep_105_loftee docker as an interactive process (like a shell), running the vep command (which we store as the variable `cmd`.

### VEP annotation using Singularity
Pull docker image built from the Dockerfile in this repo and convert to a singularity.sif.
```
singularity pull --docker-login -disable-cache "vep_data/vep.sif" "docker://ghcr.io/brava-genetics/vep105_loftee:main"
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
         --plugin LoF,loftee_path:/opt/micromamba/share/ensembl-vep-105.0-1,human_ancestor_fa:vep_data/human_ancestor.fa.gz,conservation_file:vep_data/loftee.sql,gerp_bigwig:vep_data/gerp_conservation_scores.homo_sapiens.GRCh38.bw \
         --plugin dbNSFP,vep_data/dbNSFP4.3a.txt.gz,REVEL_score,CADD_phred \
         --everything \
         --force_overwrite \
         --offline"

singularity exec --bind $(pwd):$HOME/ -W $HOME "vep_data/vep.sif" $cmd
```
As with docker, in order for our singularity container to "see" the files required for VEP annotation, you will need to mount the directory containing the required resources and the VCF to be annotated. This is what `--bind $(pwd):$HOME/` is doing. If your VCF file to be annotated is located somewhere else, you will also need to mount the directory that it sits in, or move it to the current working directory (or any subfolder within the working directory) if you're using the above code as a template. `exec` executes the command `cmd` (our VEP command) within the singularity container `vep.sif` that we've created.

## Post-processing

Now we need to determine the "worst consequence by gene on the MANE SELECT transcript (if available) or the 'canonical' transcript (if MANE SELECT isn't available)" variant annotations (wow, what a mouthful). To munge the data into a format to carry this out easily (with our python code in the [SAIGE_annotations directory of the variant-annotation repository](https://github.com/BRaVa-genetics/variant-annotation/tree/main/SAIGE_annotations), we use the BCFtools split-vep plugin). If you don't have BCFtools (we'd be surprised though), go ahead and install it following the instructions [here](https://samtools.github.io/bcftools/howtos/install.html). In order to use the BCFtools plugins, the environment variable `BCFTOOLS_PLUGIN` must be set and point to the correct location:

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
