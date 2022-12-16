# Base image https://hub.docker.com/r/rocker/verse/tags

FROM rocker/r-ver:4.0.0

ARG CRAN="https://cran.rstudio.com"

RUN install2.r --error --skipinstalled --repos ${CRAN}\
     remotes \
     data.table \
     R.utils \
     docopt

RUN Rscript -e 'remotes::install_github("CDCgov/snpeffr")' 

RUN Rscript -e 'library(snpeffr); file.copy(from = file.path(path.package("snpeffr"), "snpeffr.R"), to = getwd());'

RUN echo "export PATH=$PATH:snpeffr.R" >> /root/.bashrc

RUN chmod +x snpeffr.R
