% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/sits_plot.R
\name{.sits_plot_rgb_stack}
\alias{.sits_plot_rgb_stack}
\title{Assign RGB channels to for raster stack cubes}
\usage{
.sits_plot_rgb_stack(bands, timeline, red, green, blue, time)
}
\arguments{
\item{bands}{bands of the data cube (excludes cloud band)}

\item{timeline}{timeline of the data cube}

\item{red}{Band to be assigned to R channel}

\item{green}{Band to be assigned to G channel}

\item{blue}{Band to be assigned to G channel}

\item{time}{Temporal instance to be plotted}
}
\value{
Named vector with the correct layers for RGB
}
\description{
Obtain a vector with the correct layer to be plotted for
an RGB assignment of a multi-temporal brick cube
}
\author{
Gilberto Camara \email{gilberto.camara@inpe.br}
}
\keyword{internal}
