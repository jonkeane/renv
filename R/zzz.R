
.onLoad <- function(libname, pkgname) {

  # NOTE: needs to be visible to embedded instances of renv as well
  the$envir_self <<- renv_envir_self()

  # load extensions if available
  renv_ext_onload(libname, pkgname)

  # make sure renv (and packages using renv!!!) use tempdir for storage
  # when running tests, or R CMD check
  if (checking() || testing()) {

    # set root directory
    root <- Sys.getenv("RENV_PATHS_ROOT", unset = tempfile("renv-root-"))
    Sys.setenv(RENV_PATHS_ROOT = root)

    # unset on exit
    reg.finalizer(renv_envir_self(), function(envir) {
      if (identical(root, Sys.getenv("RENV_PATHS_ROOT", unset = NA)))
        Sys.unsetenv("RENV_PATHS_ROOT")
    }, onexit = TRUE)

    # set up sandbox -- only done on non-Windows due to strange intermittent
    # test failures that seemed to occur there?
    if (renv_platform_unix()) {
      sandbox <- Sys.getenv("RENV_PATHS_SANDBOX", unset = tempfile("renv-sandbox-"))
      Sys.setenv(RENV_PATHS_SANDBOX = sandbox)
    }

  }

  # don't lock sandbox while testing / checking
  if (testing() || checking() || devmode()) {
    options(renv.sandbox.locking_enabled = FALSE)
    Sys.setenv(RENV_SANDBOX_LOCKING_ENABLED = FALSE)
  }

  renv_defer_init()
  renv_metadata_init()
  renv_ext_init()
  renv_ansify_init()
  renv_platform_init()
  renv_virtualization_init()
  renv_envvars_init()
  renv_log_init()
  renv_methods_init()
  renv_libpaths_init()
  renv_patch_init()
  renv_sandbox_init()
  renv_sdkroot_init()
  renv_watchdog_init()
  renv_tempdir_init()

  if (!renv_metadata_embedded()) {

    # TODO: It's not clear if these callbacks are safe to use when renv is
    # embedded, but it's unlikely that clients would want them anyhow.
    renv_task_create(renv_sandbox_task)
    renv_task_create(renv_snapshot_task)
  }

  # if an renv project already appears to be loaded, then re-activate
  # the sandbox now -- this is primarily done to support suspend and
  # resume with RStudio where the user profile might not have been run,
  # but RStudio would have restored options from the prior session
  #
  # https://github.com/rstudio/renv/issues/2036
  if (renv_rstudio_available()) {
    project <- getOption("renv.project.path")
    if (!is.null(project)) {
      renv_project_set(project)
      renv_sandbox_activate(project = project)
    }
  }

  # make sure renv is unloaded on exit, so locks etc. are released
  # we previously tried to orchestrate this via unloadNamespace(),
  # but this fails when a package importing renv is already loaded
  # https://github.com/rstudio/renv/issues/1621
  reg.finalizer(renv_envir_self(), renv_unload_finalizer, onexit = TRUE)

}

.onAttach <- function(libname, pkgname) {
  renv_rstudio_fixup()
}

.onUnload <- function(libpath) {

  renv_lock_unload()
  renv_task_unload()
  renv_watchdog_unload()

  # do some extra cleanup when running R CMD check
  if (renv_platform_unix() && checking() && !ci())
    cleanse()

  # flush the help db to avoid errors on reload
  # https://github.com/rstudio/renv/issues/1294
  helpdb <- file.path(libpath, "help/renv.rdb")
  .Internal <- .Internal
  lazyLoadDBflush <- function(...) {}

  tryCatch(
    .Internal(lazyLoadDBflush(helpdb)),
    error = function(e) NULL
  )

}

# NOTE: required for devtools::load_all()
.onDetach <- function(libpath) {
  if (devmode())
    .onUnload(libpath)
}

renv_zzz_run <- function() {

  # check if we're in pkgload::load_all()
  # if so, then create some files
  if (devmode()) {
    renv_zzz_bootstrap_activate()
    renv_zzz_bootstrap_config()
  }

  # check if we're running as part of R CMD build
  # if so, build our local repository with a copy of ourselves
  if (building())
    renv_zzz_repos()

}

renv_zzz_bootstrap_activate <- function() {

  source <- "templates/template-activate.R"
  target <- "inst/resources/activate.R"
  scripts <- c("R/ansify.R", "R/bootstrap.R", "R/json-read.R")

  # Do we need an update
  source_mtime <- max(renv_file_info(c(source, scripts))$mtime)
  target_mtime <- renv_file_info(target)$mtime

  if (!is.na(target_mtime) && target_mtime > source_mtime)
    return()

  # read the necessary bootstrap scripts
  contents <- map(scripts, readLines)
  bootstrap <- unlist(contents)

  # format nicely for insertion
  bootstrap <- paste(" ", bootstrap)
  bootstrap <- paste(bootstrap, collapse = "\n")

  # replace template with bootstrap code
  template <- renv_file_read(source)
  replaced <- renv_template_replace(template, list(BOOTSTRAP = bootstrap))

  # write to resources
  printf("- Generating 'inst/resources/activate.R' ... ")
  writeLines(replaced, con = target)
  writef("Done!")

}

renv_zzz_bootstrap_config <- function() {

  source <- "inst/config.yml"
  target <- "R/config-defaults.R"

  source_mtime <- renv_file_info(source)$mtime
  target_mtime <- renv_file_info(target)$mtime

  if (target_mtime > source_mtime)
    return()

  template <- renv_template_create(heredoc(leave = 2, '
    ${NAME} = function(..., default = ${DEFAULT}) {
      renv_config_get(
        name    = "${NAME}",
        type    = "${TYPE}",
        default = default,
        args    = list(...)
      )
    }
  '))

  template <- gsub("^\\n+|\\n+$", "", template)

  generate <- function(entry) {

    name    <- entry$name
    type    <- entry$type
    default <- entry$default
    code    <- entry$code

    default <- if (length(code)) trimws(code) else deparse(default)

    replacements <- list(
      NAME     = name,
      TYPE     = type,
      DEFAULT  = default
    )

    renv_template_replace(template, replacements)

  }

  config <- yaml::read_yaml("inst/config.yml")
  code <- map_chr(config, generate)
  all <- c(
    "",
    "# Auto-generated by renv_zzz_bootstrap_config()",
    "",
    "#' @rdname config",
    "#' @export",
    "#' @format NULL",
    "config <- list(",
    "",
    paste(code, collapse = ",\n\n"),
    "",
    ")"
  )

  printf("- Generating 'R/config-defaults.R' ... ")
  writeLines(all, con = target)
  writef("Done!")

}

renv_zzz_repos <- function() {

  # don't run if we're running tests
  if (checking())
    return()

  # prevent recursion
  installing <- Sys.getenv("RENV_INSTALLING_REPOS", unset = NA)
  if (!is.na(installing))
    return()

  renv_scope_envvars(RENV_INSTALLING_REPOS = "TRUE")
  writeLines("** installing renv to package-local repository")

  # get package directory
  pkgdir <- getwd()

  # move to build directory
  tdir <- tempfile("renv-build-")
  ensure_directory(tdir)
  renv_scope_wd(tdir)

  # build renv again
  r_cmd_build("renv", path = pkgdir, "--no-build-vignettes")

  # copy built tarball to inst folder
  src <- list.files(tdir, full.names = TRUE)
  tgt <- file.path(pkgdir, "inst/repos/src/contrib")

  ensure_directory(tgt)
  file.copy(src, tgt)

  # write PACKAGES
  renv_scope_envvars(R_DEFAULT_SERIALIZE_VERSION = "2")
  write_PACKAGES(tgt, type = "source")

}

if (identical(.packageName, "renv")) {
  renv_zzz_run()
}
