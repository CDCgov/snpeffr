#' Pull in, filter, and parse vcf data and annotations from snpeff
#'
#' This function parses a vcf file generated by snpeff and filters to specific
#' genes, positions, and effects of interest. See the [snpeff](https://pcingola.github.io/SnpEff)
#' documentation for more information on
#' how to interpret these inputs and outputs.
#'
#' @param vcf_path the path to the vcf file output from snpeff (read in using data.table::fread and R.utils if zipped)
#' @param positions a named list of positions to filter to, each element can either
#'  be a sequence, i.e. 1000:2000 or a vector i.e. c(1000:2000, 300).
#' @param genes the name of the genes of interest to filter to
#' @param exclude_effects a string formatted as a regular expression,
#' effects to ignore (as categorized by snpeff, see [here](https://pcingola.github.io/SnpEff/se_inputoutput/)),
#'
#' @return a data.frame with n rows and 7 columns:
#' \describe{
#'   \item{\code{sample_id}}{ID of the sample, the names of the annotation columns from snpeff}
#'   \item{\code{snpeff_gene_name}}{name of the gene with the mutation}
#'   \item{\code{region}}{name of the region of interest, i.e. from the named list of positions,
#'                        defaults to fks1_hs1 and fks1_hs2 (fks1, hotspots 1 & 2)}
#'   \item{\code{position}}{the nucleotide position of the mutation}
#'   \item{\code{mutation}}{the protein level mutation, annotated using (HGVS notation)(http://varnomen.hgvs.org/bg-material/simple/)}
#'   \item{\code{ref_sequence}}{the nucleotide sequence for the reference}
#'   \item{\code{sample_sequence}}{the nucleotide sequence for the sample}
#' }
#'
#'
#' @export
#' @import data.table
#'
snpeffr <- function(vcf_path,
                    positions =  list(fks1_hs1 = 221638:221665, fks1_hs2 = 223782:223805),
                    genes = c("CAB11_002014"),
                    exclude_effects = "synonymous_variant") {

  vcf <- data.table::fread(file = vcf_path)

  posits <- unlist(positions, use.names = FALSE)
  names(posits) <- rep(names(positions), unlist(lapply(positions, length)))

  # filter by position
  vcf <- vcf[POS %in% posits]

  if(nrow(vcf) == 0) {
    # Create an empty data.table
    return(
      data.table("sample_id" = factor(),
                 "snpeff_gene_name" = character(),
                 "region" = character(),
                 "position" = character(),
                 "mutation" = character(),
                 "ref_sequence" = character(),
                 "sample_sequence" = character())
    )
  } else {
    # parse annotations
    # first filter to any with a functional annotation
    vcf <- vcf[grepl("ANN=", vcf$INFO)]
    vcf[, rowid := 1:nrow(vcf)]

    annots <- vcf[, tstrsplit(gsub(".*ANN=", "", INFO), split = ",", fixed=TRUE, fill="<NA>")]
    colnames(annots) <- ann_cols <- paste0("parseANN", 1:ncol(annots))

    prse_annots <- cbind(vcf[, c("rowid", "#CHROM", "POS", "REF", "ALT"), with = FALSE],
                         annots)
    ids <- colnames(prse_annots)[!grepl("parseANN", colnames(prse_annots))]
    prse_annots <- melt(prse_annots, id.vars = ids)
    prse_annots <- prse_annots[value != "<NA>"]

    # annotation order and fields from snpeff
    # http://pcingola.github.io/SnpEff/se_inputoutput/
    ann_fields <- c("allele", "effect", "putative_impact", "gene_name", "gene_id", "feature_type",
                    "feature_id", "transcript_biotype", "rank_total", "HGVS.c", "HGVS.p",
                    "cDNA_pos_len", "CDS_pos_len", "protein_pos_len", "distance")

    # parse by each annotation! (otherwise will create too large a file!)
    prsed <- prse_annots[, data.table::tstrsplit(value, split = "|", fill = "<NA>", fixed = TRUE)]
    setnames(prsed, 1:15, ann_fields)

    if(ncol(prsed) > 15) {
      extra_cols <- paste0("V", (length(ann_fields) + 1):ncol(prsed))
      prsed[, err_warn_info := Reduce(function(...) paste(..., sep = "|"), .SD), .SDcols = extra_cols]
      prsed[, err_warn_info := gsub("|<NA>", "", err_warn_info, fixed = TRUE)]
    } else {
      prsed[, err_warn_info := NA]
    }


    prse_annots <- cbind(prse_annots[, -c("variable", "value")], prsed[, ann_fields, with = FALSE])

    # filter by effects and genes

    # join up with reference and allele info
    # then parse the alternatives & bind them to the reference
    nts <- prse_annots[, tstrsplit(ALT, ",", fixed = TRUE, fill = "<NA>")]
    nts <- as.matrix(cbind(rep("", nrow(nts)), prse_annots$REF, nts)) # first row is for the dots

    # re-merging with sample info ----
    samps <- colnames(vcf)[!colnames(vcf) %in% c("#CHROM", "POS" , "ID",   "REF",  "ALT", "QUAL", "FILTER", "INFO", "FORMAT", "rowid")]
    samp_info <- vcf[, c("rowid", samps), with = FALSE]

    # just get genotypes (helper fun)
    genot <- function(x) {
      x <- sub("(.*?)[\\.|:].*", "\\1", x)
      as.numeric(fifelse(x == "", "-1", x))
    }
    samp_info[, (samps) := lapply(.SD, genot), .SDcols = samps]
    samp_info[, (samps) := lapply(.SD, function(x) nts[cbind(rowid, x + 2)]), .SDcols = samps]

    # merge with the parsed results
    vcf_prsed <- samp_info[prse_annots, on = "rowid"]
    vcf_prsed <- vcf_prsed[HGVS.p != "" & !grepl(exclude_effects, effect) & gene_id %in% genes]
    vcf_long <- melt(vcf_prsed[, c(samps, "REF", "POS", "gene_id", "effect", "ALT", "allele", "HGVS.p"), with = FALSE],
                     measure.vars = samps, variable.name = "sample_id")

    # get just the samples with mutations
    vcf_long <- vcf_long[value == allele]
    posits <- data.table(region = names(posits), POS = posits)
    vcf_long <- posits[vcf_long, on = "POS"]

    setnames(vcf_long, old = c("POS", "REF", "gene_id", "allele", "HGVS.p"),
             new = c("position", "ref_sequence", "snpeff_gene_name", "sample_sequence",
                     "mutation"))

    return(vcf_long[, c("sample_id", "snpeff_gene_name", "region", "position", "mutation",
                        "ref_sequence", "sample_sequence")])
  }


}
