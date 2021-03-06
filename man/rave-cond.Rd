% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/condition.R
\name{rave-cond}
\alias{rave-cond}
\alias{rave_condition}
\alias{rave_warn}
\alias{rave_error}
\alias{rave_fatal}
\alias{rave_info}
\alias{rave_debug}
\alias{with_rave_handlers}
\title{RAVE Internal condition classes}
\usage{
rave_condition(..., class = NULL, call = NULL, immediate. = TRUE, style = NULL)

rave_warn(..., class = NULL, call = NULL, immediate. = TRUE, style = "warn")

rave_error(..., class = NULL, call = NULL, immediate. = TRUE, style = "error")

rave_fatal(..., class = NULL, call = NULL, immediate. = TRUE, style = "fatal")

rave_info(..., class = NULL, call = NULL, immediate. = TRUE, style = "info")

rave_debug(..., class = NULL, call = NULL, immediate. = TRUE, style = "debug")

with_rave_handlers(expr, debug, info, warn, error, fatal, ...)
}
\arguments{
\item{...}{messages of \code{\link{condition}},
\code{\link[glue]{glue}} is internally supported. For
\code{with_rave_handlers}, passed to
\code{\link{withCallingHandlers}}}

\item{class}{condition class}

\item{call}{call expression}

\item{immediate.}{whether to fire condition immediately}

\item{style}{styles to apply to text; choices are \code{debug}, \code{info},
\code{warn}, \code{error}, \code{fatal}, \code{default}, or a function}

\item{expr}{expression to evaluate}

\item{debug, info, warn, error, fatal}{functions to capture signals}
}
\value{
\code{rave_error} returns \code{NULL}, others return
generated condition.
}
\description{
RAVE Internal condition classes
}
