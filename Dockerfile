# Base image https://hub.docker.com/r/rocker/verse/tags

FROM rocker/r-ver:4.0.0

ENV CRAN="https://cran.rstudio.com"

# re run to enforce environment variable
RUN /rocker_scripts/setup_R.sh

RUN install2.r --error --skipinstalled --repos ${CRAN}\
     remotes \
     data.table \
     R.utils \
     docopt

RUN Rscript -e 'remotes::install_github("CDCgov/snpeffr")' 

# Moving R script to top level of container for easy cli use
RUN Rscript -e 'library(snpeffr); file.copy(from = file.path(path.package("snpeffr"), "snpeffr.R"), to = getwd());'

RUN chmod u+x snpeffr.R

# changing cmd from R to shell for using command line tool
CMD ["bin/bash"]