#!/bin/bash
# Resources for VEP 105 + LOFTEE + dbNSFP 5.4a in vep_data/ (~45 GB when done). Resumable: rerun after a failure.
# Needs curl, unzip, python3, and bgzip + tabix (htslib) on the host.
set -euo pipefail
mkdir -p out vep_data
say() { echo "[$(date +%T)] $*"; }
get() { say "downloading $(basename "$2")"; curl -fSL -C - --retry 5 -o "$2" "$1"; }

# VEP cache, Ensembl 105 (GENCODE v39)
if [[ ! -d vep_data/homo_sapiens/105_GRCh38 ]]; then
  get https://ftp.ensembl.org/pub/release-105/variation/indexed_vep_cache/homo_sapiens_vep_105_GRCh38.tar.gz vep_data/cache.tar.gz
  say "unpacking VEP cache"; tar -xzf vep_data/cache.tar.gz -C vep_data && rm vep_data/cache.tar.gz
fi

# LOFTEE: human ancestor and GERP. Not loftee.sql (the PhyloCSF conservation database): it only adds LoF_flags
# (PHYLOCSF_*) and LoF_info, never a filter, so HC/LC do not depend on it -- and with VEP --fork it makes LOFTEE drop
# LoF calls at random (see the README, "Why no conservation database").
L=https://personal.broadinstitute.org/konradk/loftee_data/GRCh38
for f in human_ancestor.fa.gz human_ancestor.fa.gz.fai human_ancestor.fa.gz.gzi gerp_conservation_scores.homo_sapiens.GRCh38.bw; do
  [[ -s vep_data/$f ]] || get $L/$f vep_data/$f
done

# dbNSFP 5.4a (REVEL and CADD 1.7). The old 4.3a link (dbnsfp.s3.amazonaws.com) is gone, and dbNSFP 5 needs a free
# academic registration at https://www.dbnsfp.org/download: download the academic zip (dbNSFP5.4a.zip) or the
# ready-made table (dbNSFP5.4a_grch38.gz) into vep_data/ yourself, then rerun this script. It is cut to the columns
# VEP's plugin matches on plus REVEL_score and CADD_phred (~30-50 GB less than the full table).
# The file name contains 'as_v4' on purpose: VEP 105's dbNSFP plugin reads the version from the name and knows only
# 2.9/3.x/4.x; the version only picks the position column, and 5.4a uses 4.x's pos(1-based).
D=vep_data/dbNSFP5.4a_brava.as_v4.txt.gz
if [[ ! -s $D.tbi ]]; then
  G=$(ls vep_data/dbNSFP*_grch38.gz 2>/dev/null | head -1 || true)
  Z=$(ls vep_data/dbNSFP*.zip 2>/dev/null | head -1 || true)
  member() { unzip -Z1 "$Z" | grep -E "_variant\.chr$1\.gz$" | head -1; }
  if [[ -n $G ]]; then
    say "dbNSFP source: $G"; hdr=$(gzip -dc "$G" 2>/dev/null | head -1 || true)
  elif [[ -n $Z ]]; then
    [[ -n $(member 1) ]] || { say "$Z has no *_variant.chr1.gz member"; exit 3; }
    say "dbNSFP source: $Z"; hdr=$(unzip -p "$Z" "$(member 1)" | gzip -dc 2>/dev/null | head -1 || true)
  else
    say "no vep_data/dbNSFP*_grch38.gz or dbNSFP*.zip: register at https://www.dbnsfp.org/download, download dbNSFP 5.4a (academic) into vep_data/, rerun"
    exit 3
  fi
  cols=$(python3 - "$hdr" <<'PY'
import sys
h = sys.argv[1].rstrip("\n").split("\t")
keep = ["#chr", "pos(1-based)", "ref", "alt", "aaref", "aaalt", "rs_dbSNP", "hg19_chr",
        "hg19_pos(1-based)", "hg18_chr", "hg18_pos(1-based)", "aapos", "genename", "Ensembl_geneid",
        "Ensembl_transcriptid", "Ensembl_proteinid", "REVEL_score", "CADD_phred"]
miss = [k for k in keep if k not in h]
if miss or h[:4] != keep[:4]:
    sys.exit("dbNSFP header unexpected; missing %s; starts %s" % (miss, h[:4]))
print(",".join("$%d" % (h.index(k) + 1) for k in keep))
PY
)
  if [[ -n $G ]]; then
    gzip -dc "$G" | awk -F'\t' -v OFS='\t' "{print $cols}" | bgzip -c > $D.tmp
  else
    ( echo "$hdr" | awk -F'\t' -v OFS='\t' "{print $cols}"
      for c in $(seq 1 22) X Y M; do
        m=$(member $c); [[ -n $m ]] || continue
        unzip -p "$Z" "$m" | gzip -dc | awk -F'\t' -v OFS='\t' "NR > 1 {print $cols}"
      done ) | bgzip -c > $D.tmp
  fi
  mv $D.tmp $D && tabix -s 1 -b 2 -e 2 $D
  say "dbNSFP ready: $D (you can delete ${G:-$Z} now)"
fi
say "done: $(du -sh vep_data | cut -f1) in vep_data/"
