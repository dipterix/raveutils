# File IO: HDF5 file wrapper

#' @title Lazy 'HDF5' file loader
#' @author Zhengjia Wang
#' @description provides hybrid data structure for 'HDF5' file
#'
#' @examples
#' # Data to save
#' x <- array(rnorm(1000), c(10,10,10))
#'
#' # Save to local disk
#' f <- tempfile()
#' save_h5(x, file = f, name = 'x', chunk = c(10,10,10), level = 0)
#'
#' # Load via LazyFST
#' dat <- LazyH5$new(file_path = f, data_name = 'x', read_only = TRUE)
#'
#' dat
#' #> Class: H5D
#' #> Dataset: /x
#' #> Filename: ...
#' #> Access type: H5F_ACC_RDONLY
#' #> Datatype: H5T_IEEE_F64LE
#' #> Space: Type=Simple     Dims=10 x 10 x 10     Maxdims=Inf x Inf x Inf
#' #> Chunk: 11 x 11 x 11
#'
#' # Check whether the data is identical
#' range(dat - x)
#'
#' # Read a slice of the data
#' system.time(dat[,10,])
#'
#' @export
LazyH5 <- R6::R6Class(
  classname = 'LazyH5',
  portable = TRUE,
  cloneable = FALSE,
  private = list(
    file = NULL,
    name = NULL,
    read_only = TRUE,
    data_ptr = NULL,
    file_ptr = NULL,
    last_dim = NULL
  ),
  public = list(

    #' @description garbage collection method
    #' @return none
    finalize = function(){
      self$close(all = TRUE)
    },

    #' @description overrides print method
    #' @return self instance
    print = function(){
      if(!is.null(private$data_ptr)){
        if(private$data_ptr$is_valid){
          base::print(private$data_ptr)
        }else{
          base::cat('Pointer closed. Information since last open:\nDim: ',
                    paste(private$last_dim, collapse = 'x'), ' \tRank: ', length(private$last_dim))
        }
      }
      invisible(self)
    },

    #' @description constructor
    #' @param file_path where data is stored in 'HDF5' format
    #' @param data_name the data stored in the file
    #' @param read_only whether to open the file in read-only mode. It's highly
    #' recommended to set this to be true, otherwise the file connection is
    #' exclusive.
    #' @return self instance
    initialize = function(file_path, data_name, read_only = FALSE){

      # First get absolute path, otherwise hdf5r may report file not found error
      if(read_only){
        private$file = base::normalizePath(file_path)

        stopifnot2(
          hdf5r::is_hdf5(private$file),
          msg = 'File doesn\'t have H5 format'
        )
      }else{
        private$file = file_path
      }
      private$name = data_name
      private$read_only = read_only
    },

    #' @description save data to a 'HDF5' file
    #' @param x vector, matrix, or array
    #' @param chunk chunk size, length should matches with data dimension
    #' @param level compress level, from 1 to 9
    #' @param replace if the data exists in the file, replace the file or not
    #' @param new_file remove the whole file if exists before writing?
    #' @param force if you open the file in read-only mode, then saving
    #' objects to the file will raise error. Use \code{force=TRUE} to force
    #' write data
    #' @param ctype data type, see \code{\link{mode}}, usually the data type
    #' of \code{x}. Try \code{mode(x)} or \code{storage.mode(x)} as hints.
    #' @param size deprecated, for compatibility issues
    #' @param ... passed to self \code{open()} method
    save = function(x, chunk = 'auto', level = 7, replace = TRUE,
                    new_file = FALSE, force = TRUE, ctype = NULL, size = NULL,
                    ...){
      # ctype and size is deprecated but kept in case of compatibility issues
      # ptr$create_dataset =
      # function (name, robj = NULL, dtype = NULL, space = NULL, dims = NULL,
      #           chunk_dims = "auto", gzip_level = 4, link_create_pl = h5const$H5P_DEFAULT,
      #           dataset_create_pl = h5const$H5P_DEFAULT, dataset_access_pl = h5const$H5P_DEFAULT)
      if(private$read_only){
        if(!force){
          stop('File is read-only. Use "force=TRUE"')
        }else{
          # Close current pointer
          self$close(all = TRUE)
          private$read_only = FALSE

          on.exit({
            self$close(all = TRUE)
            private$read_only = TRUE
          }, add = TRUE, after = FALSE)
        }
      }

      if(new_file && file.exists(private$file)){
        self$close(all = TRUE)
        file.remove(private$file)
      }

      self$open(new_dataset = replace, robj = x, chunk = chunk, gzip_level = level, ...)

      self$close(all = TRUE)

    },


    #' @description open connection
    #' @param new_dataset only used when the internal pointer is closed, or
    #' to write the data
    #' @param robj data array to save
    #' @param ... passed to \code{\link[hdf5r]{createDataSet}}
    open = function(new_dataset = FALSE, robj, ...){

      # check data pointer
      # if valid, no need to do anything, otherwise, enter if clause
      if(new_dataset || is.null(private$data_ptr) || !private$data_ptr$is_valid){

        # Check if file is valid,
        if(is.null(private$file_ptr) || !private$file_ptr$is_valid){
          # if no, create new link
          mode = ifelse(private$read_only, 'r', 'a')
          tryCatch({
            private$file_ptr = hdf5r::H5File$new(private$file, mode)
          }, error = function(e){
            # Open for writting, we should close all connections first
            # then the file can be opened, otherwise, Access type: H5F_ACC_RDONLY
            # will lock the file for writting
            f = hdf5r::H5File$new(private$file, 'r')
            catgl('Closing all other connections to [{private$file}] - {f$get_obj_count() - 1}')
            try({ f$close_all() }, silent = TRUE)
            private$file_ptr = hdf5r::H5File$new(private$file, mode)
          })
        }

        has_data = private$file_ptr$path_valid(private$name)

        if(!private$read_only && (new_dataset || ! has_data)){
          # need to create new dataset
          g = stringr::str_split(private$name, '/', simplify = T)
          g = g[stringr::str_trim(g) != '']

          ptr = private$file_ptr
          nm = ''

          for(i in g[-length(g)]){
            nm = sprintf('%s/%s', nm, i)
            if(!ptr$path_valid(path = nm)){
              ptr = ptr$create_group(i)
              catgl('{private$file} => {nm} (Group Created)\n')
            }else{
              ptr = ptr[[i]]
            }
          }

          # create dataset
          nm = g[length(g)]
          if(ptr$path_valid(path = nm)){
            # dataset exists, unlink first
            catgl('{private$file} => {private$name} (Dataset Removed)\n')
            ptr$link_delete(nm)
          }
          # new create
          catgl('{private$file} => {private$name} (Dataset Created)\n')
          if(missing(robj)){
            robj = NA
          }
          ptr$create_dataset(nm, robj = robj, ...)
          if(ptr$is_valid && inherits(ptr, 'H5Group')){
            ptr$close()
          }
        }else if(!has_data){
          rave_fatal('File [{private$file}] has no [{private$name}] in it.')
        }

        private$data_ptr = private$file_ptr[[private$name]]

      }

      private$last_dim = private$data_ptr$dims

    },


    #' @description close connection
    #' @param all whether to close all connections associated to the data file.
    #' If true, then all connections, including access from other programs,
    #' will be closed
    close = function(all = TRUE){
      try({
        # check if data link is valid
        if(!is.null(private$data_ptr) && private$data_ptr$is_valid){
          private$data_ptr$close()
        }

        # if file link is valid, get_obj_ids() should return a vector of 1
        if(all && !is.null(private$file_ptr) && private$file_ptr$is_valid){
          private$file_ptr$close_all()
        }
      }, silent = TRUE)
    },

    #' @description subset data
    #' @param i,j,... index along each dimension
    #' @param drop whether to apply \code{\link{drop}} the subset
    #' @param stream whether to read partial data at a time
    #' @param envir if \code{i,j,...} are expressions, where should the
    #' expression be evaluated
    #' @return subset of data
    subset = function(
      ...,
      drop = FALSE, stream = FALSE,
      envir = parent.frame()
    ) {
      self$open()
      dims = self$get_dims()

      # step 1: eval indices
      args = eval(substitute(alist(...)))
      if(length(args) == 0 || (length(args) == 1 && args[[1]] == '')){
        return(private$data_ptr$read())
      }
      args = lapply(args, function(x){
        if(x == ''){
          return(x)
        }else{
          return(eval(x, envir = envir))
        }
      })

      # step 2: get allocation size
      sapply(seq_along(dims), function(ii){
        if(is.logical(args[[ii]])){
          return(sum(args[[ii]]))
        }else if(is.numeric(args[[ii]])){
          return(length(args[[ii]]))
        }else{
          # must be blank '', otherwise raise error
          return(dims[ii])
        }
      }) ->
        alloc_dim

      # step 3: get legit indices
      lapply(seq_along(dims), function(ii){
        if(is.logical(args[[ii]])){
          return(args[[ii]])
        }else if(is.numeric(args[[ii]])){
          return(
            args[[ii]][args[[ii]] <= dims[ii] & args[[ii]] > 0]
          )
        }else{
          return(args[[ii]])
        }
      }) ->
        legit_args

      # step 4: get mapping
      lapply(seq_along(dims), function(ii){
        if(is.logical(args[[ii]])){
          return(
            rep(T, sum(args[[ii]]))
          )
        }else if(is.numeric(args[[ii]])){
          return(args[[ii]] <= dims[ii] & args[[ii]] > 0)
        }else{
          return(args[[ii]])
        }
      }) ->
        mapping

      # alloc space
      re = array(NA, dim = alloc_dim)

      if(stream){
        re = do.call(`[<-`, c(list(re), mapping, list(
          value = private$data_ptr$read(
            args = legit_args,
            drop = F,
            envir = environment()
          )
        )))
      }else{
        re = do.call(`[<-`, c(list(re), mapping, list(
          value = do.call('[', c(list(private$data_ptr$read()), legit_args, list(drop = F)))
        )))
      }

      self$close(all = !private$read_only)


      if(drop){
        return(drop(re))
      }else{
        return(re)
      }
    },


    #' @description get data dimension
    #' @param stay_open whether to leave the connection opened
    #' @return dimension of the array
    get_dims = function(stay_open = TRUE){
      self$open()
      re = private$data_ptr$dims
      if(!stay_open){
        self$close(all = !private$read_only)
      }
      re
    }
  )
)

#' @export
`[.LazyH5` <- function(obj, ...){
  on.exit({obj$close()}, add = T)
  obj$subset(..., envir = parent.frame())
}

#' @export
`+.LazyH5` <- function(a, b){
  b + a$subset()
}

#' @export
`-.LazyH5` <- function(a, b){
  -(b - a$subset())
}

#' @export
`*.LazyH5` <- function(a, b){
  b * (a$subset())
}

#' @export
`/.LazyH5` <- function(a, b){
  if(inherits(b, 'LazyH5')){
    b = b$subset()
  }
  a$subset() / b
}

#' @export
dim.LazyH5 <- function(x){
  dim_info = x$get_dims(stay_open = F)
  if(length(dim_info) == 1){
    dim_info = NULL
  }
  dim_info
}

#' @export
length.LazyH5 <- function(x){
  dim_info = x$get_dims()
  prod(dim_info)
}

#' @export
as.array.LazyH5 <- function(x, ...){
  as.array(x$subset(), ...)
}

#' @export
Mod.LazyH5 <- function(z){
  base::Mod(z$subset())
}

#' @export
Arg.LazyH5 <- function(z){
  base::Arg(z$subset())
}


#' @export
exp.LazyH5 <- function(x){
  base::exp(x$subset())
}

#' Lazy Load "HDF5" File via \code{\link[hdf5r]{hdf5r-package}}
#'
#' @description Wrapper for class \code{\link[raveutils]{LazyH5}}, which load data with
#' "lazy" mode - only read part of dataset when needed.
#'
#' @param file "HDF5" file
#' @param name \code{group/data_name} path to dataset
#' @param read_only default is TRUE, read dataset only
#' @param ram load to RAM immediately
#'
#' @seealso \code{\link[raveutils]{save_h5}}
#' @export
load_h5 <- function(file, name, read_only = TRUE, ram = FALSE){

  re = tryCatch({
    re = LazyH5$new(file_path = file, data_name = name, read_only = read_only)
    re$open()
    re
  }, error = function(e){

    if(!read_only){
      stop('Another process is locking the file. Cannot open file with write permission; use ', sQuote('save_h5'), ' instead...\n  file: ', file, '\n  name: ', name)
    }
    catgl('Open failed. Attempt to open with a temporary copy...')

    # Fails when other process holds a connection to it!
    # If read_only, then copy the file to local directory
    tmpf = tempfile(fileext = 'conflict.h5')
    file.copy(file, tmpf)
    LazyH5$new(file_path = tmpf, data_name = name, read_only = read_only)
  })

  if(ram){
    f = re
    re = re[]
    f$close()
  }
  re
}









#' Save objects to "HDF5" file without trivial checks
#' @param x array, matrix, or vector
#' @param file \code{HDF5} file
#' @param name path to dataset in format like \code{"group/data_name"}
#' @param chunk chunk size
#' @param level compress level
#' @param replace if dataset exists, replace?
#' @param new_file remove old file if exists?
#' @param ctype dataset type: numeric? character?
#' @param ... passed to other \code{LazyH5$save}
#'
#' @seealso \code{\link{load_h5}}
#' @examples
#'
#' file <- tempfile()
#' x <- 1:120; dim(x) <- 2:5
#'
#' # save x to file with name /group/dataset/1
#' save_h5(x, file, '/group/dataset/1', chunk = dim(x))
#'
#' # read data
#' y <- load_h5(file, '/group/dataset/1')
#' y[]
#' @export
save_h5 <- function(x, file, name, chunk = 'auto', level = 4,replace = TRUE, new_file = FALSE, ctype = NULL, ...){
  f = tryCatch({
    f = LazyH5$new(file, name, read_only = FALSE)
    f$open()
    f$close()
    f
  }, error = function(e){
    catgl('Saving failed. Attempt to unlink the file and retry...', level = 'INFO')
    if(file.exists(file)){
      # File is locked,
      tmpf = tempfile(fileext = 'conflict.w.h5')
      file.copy(file, tmpf)
      unlink(file, recursive = FALSE, force = TRUE)
      file.copy(tmpf, file)
      unlink(tmpf)
    }
    # Otherwise it's some wierd error, or dirname not exists, expose the error
    LazyH5$new(file, name, read_only = FALSE)
  })
  on.exit({
    f$close(all = TRUE)
  }, add = TRUE)
  f$save(x, chunk = chunk, level = level, replace = replace, new_file = new_file, ctype = ctype, force = TRUE, ...)

  return()
}
