# Dockerfile adapted from https://github.com/populationgenomics/images/blob/main/images/vep/Dockerfile
FROM debian:bookworm-slim

ENV MAMBA_ROOT_PREFIX=/opt/micromamba
ENV PATH=$MAMBA_ROOT_PREFIX/bin:$PATH
ARG VERSION=${VERSION:-105.0}

# Install required packages
RUN apt-get update && \
    apt-get install -y \
      bash \
      bzip2 \
      curl \
      git \
      gnupg2 \
      lsb-release \
      wget \
      zip && \
    rm -r /var/lib/apt/lists/* && \
    rm -r /var/cache/apt/*

# Install micromamba
RUN curl -sL https://api.anaconda.org/download/conda-forge/micromamba/0.8.2/linux-64/micromamba-0.8.2-he9b6cbd_0.tar.bz2 | tar -xvj -C /usr/local bin/micromamba && \§
    mkdir $MAMBA_ROOT_PREFIX && \
    micromamba install -y --prefix $MAMBA_ROOT_PREFIX -c bioconda -c conda-forge \
      ensembl-vep=${VERSION} \
      google-cloud-sdk

# Install Loftee dependencies
RUN micromamba install -y --prefix $MAMBA_ROOT_PREFIX -c bioconda -c conda-forge \
      perl-bio-bigfile \
      perl-dbd-sqlite \
      perl-list-moreutils \
      samtools

# Install and configure Loftee
RUN rm -r /opt/micromamba/pkgs && \
    VEP_SHARE=$MAMBA_ROOT_PREFIX/share/ensembl-vep-$VERSION-* && \
    rm $VEP_SHARE/TissueExpression.pm $VEP_SHARE/ancestral.pm $VEP_SHARE/context.pm $VEP_SHARE/de_novo_donor.pl $VEP_SHARE/extended_splice.pl $VEP_SHARE/gerp_dist.pl $VEP_SHARE/loftee_splice_utils.pl $VEP_SHARE/splice_site_scan.pl $VEP_SHARE/svm.pl $VEP_SHARE/utr_splice.pl && \
    git clone https://github.com/populationgenomics/loftee_38.git && \
    cp -r loftee_38/* $VEP_SHARE && \
    rm -rf loftee_38 && \
    echo "export PERL5LIB=/:$MAMBA_ROOT_PREFIX/share/ensembl-vep" >> /etc/bash.bashrc && \
    echo "export LOFTEE_PLUGIN_PATH=$MAMBA_ROOT_PREFIX/share/ensembl-vep" >> /etc/bash.bashrc

# Install BioPerl for Loftee
RUN vep_install --AUTO a --NO_UPDATE --NO_HTSLIB --DESTDIR $MAMBA_ROOT_PREFIX/share/ensembl-vep-$VERSION* && \
    ln -fs $MAMBA_ROOT_PREFIX/share/ensembl-vep-$VERSION* $MAMBA_ROOT_PREFIX/share/ensembl-vep
