#' @title Obtains the timeline
#' @name sits_timeline
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description This function returns the timeline for a given data set
#'              For details see:
#' \itemize{
#'  \item{"time series": }{see \code{\link{sits_timeline.sits}}}
#'  \item{"data cube": }{see \code{\link{sits_timeline.cube}}}
#' }
#' @param  data     either a sits tibble or data cube
#' @export
sits_timeline <- function(data) {
    # get the meta-type (sits or cube)
    data <- .sits_config_data_meta_type(data)

    UseMethod("sits_timeline", data)
}
#'
#' @title Obtains the timeline for a set of time series
#' @name sits_timeline.sits
#' @param  data     A sits tibble
#' @export
sits_timeline.sits <- function(data) {
    timeline <- NULL

    timeline <- lubridate::as_date(sits_time_series_dates(data))

    assertthat::assert_that(!purrr::is_null(timeline),
        msg = "sits_timeline: input does not contain a valid timeline"
    )

    return(timeline)
}
#'
#' @title Obtains the timeline for a data cube
#' @name sits_timeline.cube
#' @param  data     A sits tibble (either a sits tibble or a raster metadata).
#' @export
sits_timeline.cube <- function(data) {
    timeline <- NULL
    # is this a cube metadata?
    timeline <- lubridate::as_date(data$timeline[[1]][[1]])

    assertthat::assert_that(!purrr::is_null(timeline),
        msg = "sits_timeline: input does not contain a valid timeline"
    )

    # check that all timelines are the same
    return(timeline)
}

#' @title Check cube timeline against requested start and end dates
#' @name .sits_timeline_check_cube
#' @keywords internal
#'
#' @description Tests if required start and end dates are available in
#'              the data cube
#'
#' @param cube            Data cube metadata.
#' @param start_date      Start date of the period.
#' @param end_date        End date of the period.
#'
#' @return A vector with corrected start and end dates

.sits_timeline_check_cube <- function(cube, start_date, end_date) {
    # get the timeline
    timeline <- sits_timeline(cube)
    # if null use the cube timeline, else test if dates are valid
    if (purrr::is_null(start_date)) {
          start_date <- lubridate::as_date(timeline[1])
      } else {
          assertthat::assert_that(start_date >= timeline[1],
              msg = "start_date is not inside the cube timeline"
          )
      }
    if (purrr::is_null(end_date)) {
          end_date <- lubridate::as_date(timeline[length(timeline)])
      } else {
          assertthat::assert_that(end_date <= timeline[length(timeline)],
              msg = "end_date is not inside the cube timeline"
          )
      }

    # build a vector to return the values
    start_end <- c(lubridate::as_date(start_date), lubridate::as_date(end_date))
    names(start_end) <- c("start_date", "end_date")

    return(start_end)
}

#' @title Define the information required for classifying time series
#' @name .sits_timeline_class_info
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Time series classification requires a series of steps:
#' (a) Provide labelled samples that will be used as training data.
#' (b) Provide information on how the classification will be performed,
#'     including data timeline,and start and end dates per interval.
#' (c) Clean the training data to ensure it meets the specifications
#'     of the classification info.
#' (d) Use the clean data to train a machine learning classifier.
#' (e) Classify non-labelled data sets.
#'
#' In this set of steps, this function provides support for step (b).
#' It requires the user to provide a timeline, the classification interval,
#' and the start and end dates of the reference period. T
#' he results is a tibble with information that allows the user
#' to perform steps (c) to (e).
#'
#' @param  data            Description on the data being classified.
#' @param  samples         Samples used for training the classification model.
#' @return A tibble with the classification information.
.sits_timeline_class_info <- function(data, samples) {

    # find the timeline
    timeline <- sits_timeline(data)

    # precondition is the timeline correct?
    assertthat::assert_that(length(timeline) > 0,
        msg = "sits_timeline_class_info: invalid timeline"
    )

    # precondition: are the samples valid?
    .sits_test_tibble(samples)

    # find the labels
    labels <- sits_labels(samples)$label
    # find the bands
    bands <- sits_bands(samples)

    # what is the reference start date?
    ref_start_date <- lubridate::as_date(samples[1, ]$start_date)
    # what is the reference end date?
    ref_end_date <- lubridate::as_date(samples[1, ]$end_date)

    # number of samples
    num_samples <- nrow(samples[1, ]$time_series[[1]])

    # obtain the reference dates that match the patterns in the full timeline
    ref_dates <- .sits_timeline_match(timeline,
                                      ref_start_date,
                                      ref_end_date,
                                      num_samples)

    # obtain the indexes of the timeline that match the reference dates
    dates_index <- .sits_timeline_match_indexes(timeline, ref_dates)

    # find the number of the samples
    nsamples <- dates_index[[1]][2] - dates_index[[1]][1] + 1

    class_info <- tibble::tibble(
        bands = list(bands),
        labels = list(labels),
        timeline = list(timeline),
        num_samples = nsamples,
        ref_dates = list(ref_dates),
        dates_index = list(dates_index)
    )
    return(class_info)
}

#' @title Find the time index of the blocks to be extracted for classification
#' @name .sits_timeline_index_blocks
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Obtains the indexes of the blocks for each time interval
#' associated with classification.
#'
#' @param class_info Tibble with information required for classification.
#' @return Indexes of the input data set associated to each time interval
#' used for classification.
.sits_timeline_index_blocks <- function(class_info) {
    # find the subsets of the input data
    dates_index <- class_info$dates_index[[1]]

    # retrieve the timeline of the data
    timeline <- class_info$timeline[[1]]

    # retrieve the bands
    bands <- class_info$bands[[1]]

    # retrieve the time index
    time_index <- .sits_timeline_idx_from_dates(dates_index, timeline, bands)

    return(time_index)
}

#' @title Test if date fits with the timeline
#' @name .sits_timeline_valid_date
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description A timeline is a list of dates where observations are available.
#' This function estimates if a date is valid by comparing it to the timeline.
#' If the date's estimate is not inside the timeline and the difference between
#' the date and the first date of timeline is greater than the acquisition
#' interval of the timeline, the date is not valid.
#'
#' @param date        A date.
#' @param timeline    A vector of reference dates.
#' @return Is this is valid starting date?
.sits_timeline_valid_date <- function(date, timeline) {

     # is the date inside the timeline?
    if (date %within% lubridate::interval(timeline[1],
                                          timeline[length(timeline)]))
        return(TRUE)

    # what is the difference in days between the last two days of the timeline?
    timeline_diff <- as.integer(timeline[2] - timeline[1])
    # if the difference in days in the timeline is smaller than the difference
    # between the reference date and the first date of the timeline, then
    # we assume the date is valid
    if (abs(as.integer(date - timeline[1])) <= timeline_diff) {
        return(TRUE)
    }
    # what is the difference in days between the last two days of the timeline?
    timeline_diff <- as.integer(timeline[length(timeline)] -
                                  timeline[length(timeline) - 1])

    # if the difference in days in the timeline is smaller than the difference
    # between the reference date and the last date of the timeline, then
    # we assume the date is valid
    if (abs(as.integer(date - timeline[length(timeline)])) <= timeline_diff) {
      return(TRUE)
    }

    return(FALSE)
}

#' @title Find dates in the input data cube that match those of the patterns
#' @name .sits_timeline_match
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description For correct classification, the input data set
#'              should be aligned to that of the reference data set.
#'              This function aligns these data sets.
#'
#' @param timeline              timeline of input observations (vector).
#' @param ref_start_date        reference for starting the classification.
#' @param ref_end_date          reference for end the classification.
#' @param num_samples           number of samples.
#' @return A list of breaks that will be applied to the input data set.
#' @examples
#' # get a timeline for MODIS data
#' data("timeline_2000_2017")
#' # get a set of subsets for a period of 10 years
#' ref_start_date <- lubridate::ymd("2000-08-28")
#' ref_end_date <- lubridate::ymd("2000-08-13")
#' nsamples <- 23
#' dates <- sits:::.sits_timeline_match(timeline_2000_2017,
#'                  ref_start_date, ref_end_date, nsamples)
#' @export
.sits_timeline_match <- function(timeline,
                                 ref_start_date,
                                 ref_end_date,
                                 num_samples) {

    # make sure the timelines is a valid set of dates
    timeline <- lubridate::as_date(timeline)

    # define the input start and end dates
    input_start_date <- timeline[1]

    # what is the expected start and end dates based on the patterns?
    ref_st_mday <- as.character(lubridate::mday(ref_start_date))
    ref_st_month <- as.character(lubridate::month(ref_start_date))
    year_st_date <- as.character(lubridate::year(input_start_date))
    est_start_date <- lubridate::as_date(paste0(year_st_date, "-",
                                                ref_st_month, "-",
                                                ref_st_mday)
                                         )
    # find the actual starting date by searching the timeline
    idx_start_date <- which.min(abs(est_start_date - timeline))
    start_date <- timeline[idx_start_date]

    # is the start date a valid one?
    assertthat::assert_that(.sits_timeline_valid_date(start_date, timeline),
        msg = ".sits_timeline_match: start date in not inside timeline"
    )

    # obtain the subset dates to break the input data set
    # adjust the dates to match the timeline
    subset_dates <- list()

    # what is the expected end date of the classification?
    idx_end_date <- idx_start_date + (num_samples - 1)

    end_date <- timeline[idx_end_date]

    # is the start date a valid one?
    assertthat::assert_that(!(is.na(end_date)),
        msg = ".sits_timeline_match: start and end date do not match timeline /n
                            Please compare your timeline with your samples"
    )

    # go through the timeline of the data
    # find the reference dates for the classification
    while (!is.na(end_date)) {
        # add the start and end date
        subset_dates[[length(subset_dates) + 1]] <- c(start_date, end_date)

        # estimate the next start and end dates
        idx_start_date <- idx_end_date + 1
        start_date <- timeline[idx_start_date]
        idx_end_date <- idx_start_date + num_samples - 1
        # estimate
        end_date <- timeline[idx_end_date]
    }
    # is the end date a valid one?
    end_date <- subset_dates[[length(subset_dates)]][2]
    assertthat::assert_that(.sits_timeline_valid_date(end_date, timeline),
        msg = ".sits_timeline_match: end_date not inside timeline"
    )

    return(subset_dates)
}

#' @title Find indexes in a timeline that match the reference dates
#' @name .sits_timeline_match_indexes
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description For correct classification, the time series of the input data
#'              should be aligned to that of the reference data set
#'              (usually a set of patterns).
#'              This function aligns these data sets so that shape
#'              matching works correctly
#'
#' @param timeline      Timeline of input observations (vector).
#' @param ref_dates     List of breaks to be applied to the input data set.
#' @return              A list of indexes that match the reference dates
#'                      to the timelines.
#'
.sits_timeline_match_indexes <- function(timeline, ref_dates) {
    dates_index <- ref_dates %>%
        purrr::map(function(date_pair) {
            start_index <- which(timeline == date_pair[1])
            end_index <- which(timeline == date_pair[2])

            dates_index <- c(start_index, end_index)
            return(dates_index)
        })

    return(dates_index)
}

#' @title Indexes to extract data from a distance table for classification
#' @name .sits_timeline_dist_indexes
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Given a list of time indexes that indicate
#'              the start and end of the values to
#'              be extracted to classify each band,
#'              obtain a list of indexes that will be used to
#'              extract values from a combined distance tibble
#'              (which has all the bands put together).
#'
#' @param  class_info         Tibble with classification information.
#' @param  ntimes             Number of time instances.
#' @return List of indexes to be extracted for each classification interval.
#'
.sits_timeline_dist_indexes <- function(class_info, ntimes) {
    # find the subsets of the input data
    dates_index <- class_info$dates_index[[1]]

    # retrieve the timeline of the data
    timeline <- class_info$timeline[[1]]

    # retrieve the bands
    bands <- class_info$bands[[1]]
    n_bands <- length(bands)
    assertthat::assert_that(n_bands > 0,
        msg = "no bands in cube"
    )

    # retrieve the time index
    time_index <- .sits_timeline_idx_from_dates(dates_index, timeline, bands)

    size_lst <- n_bands * ntimes + 2

    dist_indexes <- purrr::map(time_index, function(idx) {
        # for a given time index, build the data.table to be classified
        # build the classification matrix extracting the relevant columns
        dist_idx <- logical(length = size_lst)
        dist_idx[1:2] <- TRUE
        for (b in 1:n_bands) {
            i1 <- idx[(2 * b - 1)] + 2
            i2 <- idx[2 * b] + 2
            dist_idx[i1:i2] <- TRUE
        }
        return(dist_idx)
    })
    return(dist_indexes)
}

#' @title Provide a list of indexes to extract data from a raster-derived
#'        data table for classification
#' @name .sits_timeline_raster_indexes
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @description Given a list of time indexes that indicate the start and end
#'              of the values to be extracted to classify each band,
#'              obtain a list of indexes that will be used to extract values
#'              from a combined distance tibble
#'              (which has all the bands put together).
#'
#' @param  cube               Data cube with input data set.
#' @param  samples            Tibble with samples used for classification.
#' @return List of values to be extracted for each classification interval.
.sits_timeline_raster_indexes <- function(cube, samples) {
    # define the classification info parameters
    class_info <- .sits_timeline_class_info(data = cube, samples = samples)

    # define the time indexes required for classification
    time_indexes <- .sits_timeline_index_blocks(class_info)

    # find the length of the timeline
    ntimes <- length(sits_timeline(cube))

    # get the bands in the same order as the samples
    n_bands <- length(sits_bands(samples))
    assertthat::assert_that(n_bands > 0,
        msg = "no bands in samples"
    )

    size_lst <- n_bands * ntimes + 2

    select_lst <- purrr::map(time_indexes, function(idx) {
        # for a given time index, build the data.table to be classified
        # build the classification matrix extracting the relevant columns
        select <- logical(length = size_lst)
        select[1:2] <- TRUE
        for (b in 1:n_bands) {
            i1 <- idx[(2 * b - 1)] + 2
            i2 <- idx[2 * b] + 2
            select[i1:i2] <- TRUE
        }
        return(select)
    })
    return(select_lst)
}

#' @title Create a list of time indexes from the dates index
#' @name  .sits_timeline_idx_from_dates
#' @keywords internal
#' @author Gilberto Camara, \email{gilberto.camara@@inpe.br}
#'
#' @param  dates_index  A list of dates with the subsets of the input data.
#' @param  timeline     The timeline of the data set.
#' @param  bands        Bands used for classification.
#' @return              The subsets of the timeline.
.sits_timeline_idx_from_dates <- function(dates_index, timeline, bands) {
    # transform the dates index (a list of dates) to a list of indexes
    # this speeds up extracting the distances for classification
    n_bands <- length(bands)
    time_index <- dates_index %>%
        purrr::map(function(idx) {
            idx_lst <- seq_len(n_bands) %>%
              purrr::map(function(b){
                idx1 <- idx[1] + (b - 1) * length(timeline)
                idx2 <- idx[2] + (b - 1) * length(timeline)
                return(c(idx1, idx2))
              })
            index_ts <- unlist(idx_lst)
            return(index_ts)
        })
    return(time_index)
}
#' @title Given a start and end date, find the indexes in a timeline
#' @name  .sits_timeline_indexes
#' @keywords internal
#'
#' @param timeline      A valid timeline
#' @param start_date    A date inside the timeline
#' @param end_date      A date inside the timeline
#' @return              Named vector with start and end indexes
#'
.sits_timeline_indexes <- function(timeline,
                                   start_date = NULL,
                                   end_date = NULL) {
    # indexes for extracting data from the timeline
    start_idx <- 1
    end_idx <- length(timeline)
    # obtain the start and end indexes
    if (!purrr::is_null(start_date)) {
        start_idx <- which.min(abs(lubridate::as_date(start_date) - timeline))
    }
    if (!purrr::is_null(end_date)) {
        end_idx <- which.min(abs(lubridate::as_date(end_date) - timeline))
    }
    time_idx <- c(start_idx, end_idx)
    names(time_idx) <- c("start_idx", "end_idx")
    return(time_idx)
}

#' @title Find if the date information is correct
#' @name  .sits_timeline_date_format
#' @keywords internal
#'
#' @description Given a information about dates, check if the date can be
#'              interpreted by lubridate
#'
#' @param file_info     a tibble with date and band information
#' @return              Tibble with corrected date information
#'
.sits_timeline_date_format <- function(date_band) {
    assertthat::assert_that(nrow(date_band) > 0,
        msg = "invalid date and band information"
    )

    assertthat::assert_that(all(colnames(date_band) %in% c("date", "band")),
        msg = "error in obtaining date and band information"
    )

    # tries to convert date information to a lubridate known format
    tryCatch({
            date_band <- dplyr::mutate(date_band,
                date = lubridate::as_date(as.character(date))
            )
        },
        error = function(e) {
            stop("Invalid date format in file", call. = FALSE)
        },
        warning = function(w) {
            stop("Invalid date format in file", call. = FALSE)
        }
    )

    return(date_band)
}
