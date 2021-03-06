% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/validate.R
\name{get_val2}
\alias{get_val2}
\title{Get Value or Default if Value is Invalid}
\usage{
get_val2(x, key = NA, default = NULL, na = FALSE, min_len = 1L, ...)
}
\arguments{
\item{x}{a list, or environment, or just any R object}

\item{key}{the name to obtain from \code{x}. If \code{NA}, then
return x. Default is \code{NA}}

\item{default}{default value if}

\item{na, min_len, ...}{passed to \code{\link{is_valid_ish}}}
}
\description{
Get Value or Default if Value is Invalid
}
