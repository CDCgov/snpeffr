# Base image https://hub.docker.com/r/rocker/verse/tags

FROM rocker/r-ver:4.0.0

# Package dependecies include: R.utils, data.table and docopt

ARG CRAN="https://cran.rstudio.com"

RUN install2.r --error --skipinstalled --repos ${CRAN}\
    remotes \
    data.table \
    R.utils \
    docopt

RUN Rscript -e 'remotes::install_url("")'

