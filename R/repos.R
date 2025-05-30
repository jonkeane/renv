
renv_repos_normalize <- function(repos = getOption("repos")) {

  # ensure repos are a character vector
  repos <- convert(repos, "character")

  # force a CRAN mirror when needed
  cran <- getOption("renv.repos.cran", "https://cloud.r-project.org")
  repos[repos == "@CRAN@"] <- cran

  # ensure all values are named
  names(repos) <- renv_repos_names(repos)

  # return normalized repository
  repos

}

renv_repos_names <- function(repos) {

  result <- enum_chr(repos, function(name, repo) {

    # if we already have a name, use it
    if (nzchar(name %||% ""))
      return(name)

    # if this repository matches a known CRAN mirror, call it CRAN
    mirrors <- renv_cran_mirrors()
    if (any(renv_repos_matches(repo, mirrors)))
      return("CRAN")

    # otherwise, just use the repository URL as the name
    repo

  })

  unname(result)

}

renv_repos_validate <- function(repos = getOption("repos")) {

  # allow empty repository explicitly
  if (empty(repos))
    return(character())

  # otherwise, ensure it's a named list or character vector
  ok <- is.list(repos) || is.character(repos)
  if (!ok)
    stopf("repos has unexpected type '%s'", typeof(repos))

  # read repository names
  nm <- names(repos) %||% rep.int("", length(repos))
  if (any(nm %in% "")) {

    # if this is a length-one repository, assume it's CRAN
    if (length(repos) == 1L) {
      repos <- c(CRAN = repos)
      return(renv_repos_normalize(repos))
    }

    # otherwise, error
    stopf("all repository entries must be named")

  }

  # normalize the repos option
  renv_repos_normalize(repos)

}

renv_repos_info <- function(url) {

  memoize(
    key   = url,
    value = renv_repos_info_impl(url)
  )

}

renv_repos_info_impl <- function(url) {

  # make sure the repository URL includes a trailing slash
  url <- gsub("/*$", "/", url)

  # if this is a file repository, return early
  if (grepl("^file:", url))
    return(list(nexus = FALSE))

  # try to download it
  destfile <- renv_scope_tempfile("renv-repos-")
  status <- catch(download(url, destfile = destfile, quiet = TRUE))
  if (inherits(status, "error"))
    return(status)

  # read the contents of the page
  contents <- renv_file_read(destfile)

  # determine if this is a Nexus repository
  nexus <-
    grepl("Nexus Repository Manager", contents, fixed = TRUE) ||
    grepl("<div class=\"nexus-header\">", contents, fixed = TRUE)

  list(
    nexus = nexus
  )

}

renv_repos_matches <- function(url, repos) {
  url   <- sub("/$", "", as.character(url))
  repos <- sub("/$", "", as.character(repos))
  url %in% repos
}
