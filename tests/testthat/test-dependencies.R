
test_that("can select fields", {

  renv_tests_scope()
  expect_equal(renv_dependencies_impl(field = "Package"), character())

  writeLines("library(utils)", "deps.R")
  expect_equal(renv_dependencies_impl(field = "Package"), "utils")

})

test_that(".Rproj files requesting devtools is handled", {
  renv_tests_scope()
  writeLines("PackageUseDevtools: Yes", "project.Rproj")
  deps <- dependencies(dev = TRUE)
  packages <- deps$Package
  expect_setequal(packages, c("devtools", "roxygen2"))
})

test_that("usages of library, etc. are properly handled", {

  deps <- dependencies("resources/code.R")
  pkgs <- deps$Package

  expect_equal(pkgs, tolower(pkgs))

  l <- pkgs[nchar(pkgs) == 1]
  expect_equal(sort(l), letters[seq_along(l)])

})

test_that("parse errors are okay in .Rmd documents", {
  deps <- dependencies("resources/chunk-errors.Rmd")
  pkgs <- deps$Package
  expect_setequal(pkgs, c("rmarkdown", "dplyr"))
})

test_that("inline chunks are parsed for dependencies", {
  deps <- dependencies("resources/inline-chunks.Rmd")
  pkgs <- deps$Package
  expect_setequal(pkgs, c("rmarkdown", "inline", "multiple", "separate"))
})

test_that("usages of S4 tools are discovered", {
  file <- renv_test_code({setClass("ClassSet")})
  deps <- dependencies(file)
  expect_true(deps$Package == "methods")
})

test_that("the package name is validated when inferring dependencies", {
  file <- renv_test_code({SomePackage::setClass("ClassSet")})
  deps <- dependencies(file)
  expect_true("SomePackage" %in% deps$Package)
  expect_false("methods" %in% deps$Package)
})

test_that("empty chunks don't cause issues during dependency resolution", {
  deps <- dependencies("resources/empty-chunk.Rmd")
  pkgs <- deps$Package
  expect_setequal(pkgs, c("rmarkdown"))
})

test_that("pacman::p_load() usages are understood", {
  deps <- dependencies("resources/pacman.R")
  packages <- setdiff(deps$Package, "pacman")
  expect_setequal(packages, letters[1:length(packages)])
})

test_that("import:: usages are understood", {
  deps <- dependencies("resources/import.R")
  packages <- setdiff(deps$Package, "import")
  expect_setequal(packages, letters[1:length(packages)])
})

test_that("box::use() usages are handled", {
  deps <- dependencies(test_path("resources/box.R"))
  actual <- deps$Package
  expected <- c("A", "B", "C", "D", "box")
  expect_setequal(actual, expected)
})

test_that("targets::tar_option_set() dependencies are handled", {
  deps <- dependencies("resources/targets.R")
  expect_setequal(deps$Package, c("A", "B", "targets"))
})

test_that("renv warns when large number of files found in total", {

  renv_scope_options(renv.config.dependencies.limit = 5L)
  strip_dir <- function(x) gsub(basename(getwd()), "<project-dir>", x)

  renv_tests_scope()
  dir.create("a")
  dir.create("b")
  file.create(sprintf("a/%.3i.R", 1:3))
  file.create(sprintf("b/%.3i.R", 1:3))
  expect_snapshot(. <- dependencies())

})

test_that("renv warns when large number of files found in one directory", {

  renv_scope_options(renv.config.dependencies.limit = 5L)

  renv_tests_scope()
  file.create(sprintf("%.3i.R", 1:10))
  expect_snapshot(. <- dependencies())

})


test_that("evil knitr chunks are handled", {
  deps <- dependencies("resources/evil.Rmd")
  packages <- deps$Package
  expect_setequal(packages, c("rmarkdown", "a", "b"))
})

test_that("renv_dependencies_requires warns once", {
  expect_warning(renv_dependencies_require("nosuchpackage", "test"))
  expect_false(renv_dependencies_require("nosuchpackage", "test"))
})

test_that("the presence of an rsconnect folder forces dependency on rsconnect", {
  renv_tests_scope()
  dir.create("rsconnect")
  deps <- dependencies()
  expect_true("rsconnect" %in% deps$Package)
})

test_that("dependencies can accept multiple files", {

  deps <- dependencies(
    path = c("packages/bread", "packages/breakfast"),
    root = getwd()
  )

  expect_setequal(deps$Package, c("oatmeal", "toast"))

})

test_that("no warnings are produced when crawling dependencies", {

  expect_warning(
    regexp = NA,
    dependencies(
      "resources",
      root = file.path(getwd(), "resources")
    )
  )

})

test_that("Suggests are dev. deps for all projects", {

  renv_tests_scope()

  expected <- data.frame(
    Package = "bread",
    Dev = TRUE,
    stringsAsFactors = FALSE
  )

  writeLines(c("Type: Project", "Suggests: bread"), con = "DESCRIPTION")
  deps <- dependencies(dev = TRUE)
  expect_equal(deps[c("Package", "Dev")], expected)

  writeLines(c("Type: Package", "Suggests: bread"), con = "DESCRIPTION")
  deps <- dependencies(dev = TRUE)
  expect_equal(deps[c("Package", "Dev")], expected)

})

test_that("packages referenced by modules::import() are discovered", {
  deps <- dependencies("resources/modules.R")
  expect_setequal(deps$Package, c("A", "B", "C", "D", "G", "H", "modules"))
})

# https://github.com/rstudio/renv/issues/2007
test_that("module without parameter doesn't give an error", {
  deps <- dependencies("resources/modules-empty.R")
  expect_setequal(deps$Package, character())
})

test_that("dependencies specified in R Markdown site generators are found", {

  renv_tests_scope()
  writeLines(
    c("---", "site: blogdown:::blogdown_site", "---"),
    con = "index.Rmd")
  deps <- dependencies()
  expect_true("blogdown" %in% deps$Package)
  writeLines(
    c("---", "site: bookdown::bookdown_site", "---"),
    con = "index.Rmd")
  deps <- dependencies()
  expect_true("bookdown" %in% deps$Package)

})

test_that("Suggest dependencies are ignored by default", {
  renv_tests_scope("breakfast")
  install("breakfast")
  expect_false(renv_package_installed("egg"))
})

test_that("a call to geom_hex() implies a dependency on ggplot2", {

  file <- renv_test_code({
    ggplot() + geom_hex()
  })

  deps <- dependencies(file)
  expect_true("hexbin" %in% deps$Package)

})

test_that("empty fields are handled in DESCRIPTION", {
  deps <- dependencies("resources/DESCRIPTION")
  expect_setequal(deps$Package, c("a", "b", "c"))
})

test_that("recursive symlinks are handled", {
  skip_on_os("windows")

  project <- renv_scope_tempfile()
  ensure_directory(project)

  renv_scope_wd(project)

  symlink <- file.path(project, "symlink")
  file.symlink(dirname(symlink), symlink)

  dependencies()

})

test_that("exercise chunks are ignored", {
  deps <- dependencies("resources/learnr-exercise.Rmd")
  expect_true("A" %in% deps$Package)
})

test_that("dependencies in R functions can be found", {
  deps <- dependencies(function() renv::init)
  expect_true("renv" %in% deps$Package)
})

test_that("dependencies in dotfiles are discovered", {
  renv_tests_scope()
  writeLines("library(A)", con = ".Rprofile")
  deps <- dependencies()
  expect_true(nrow(deps) == 1L)
  expect_true(basename(deps$Source) == ".Rprofile")
  expect_true(deps$Package == "A")
})

test_that("reused knitr chunks are handled", {
  deps <- dependencies("resources/knitr-reused-chunks.Rmd")
  expect_true(all(c("A", "B") %in% deps$Package))
})

test_that("empty / missing labels are handled", {
  deps <- dependencies("resources/empty-label.Rmd")
  expect_true(all(c("A", "B") %in% deps$Package))
})

test_that("only dependencies in a top-level DESCRIPTION file are used", {
  renv_tests_scope()

  dir.create("a")
  writeLines("Depends: toast", con = "DESCRIPTION")
  writeLines("Depends: oatmeal", con = "a/DESCRIPTION")

  deps <- dependencies()
  expect_true("toast" %in% deps$Package)
  expect_false("oatmeal" %in% deps$Package)

})

test_that("multiple output formats are handled", {
  deps <- dependencies("resources/multiple-output-formats.Rmd")
  expect_true("bookdown" %in% deps$Package)
})

test_that("glue::glue() package usages are found", {
  deps <- dependencies("resources/glue.R")
  expect_true(all(c("A", "B", "C", "D", "E", "F", "G") %in% deps$Package))
  expect_false(any(letters %in% deps$Package))
})

test_that("set_engine() package usages are found", {
  deps <- dependencies("resources/parsnip.R")
  expect_setequal(deps$Package, c("glmnet"))
})

test_that("eval=F does not trip up dependencies", {
  deps <- dependencies("resources/eval.Rmd")
  expect_true("A" %in% deps$Package)
  expect_false("a" %in% deps$Package)
})

test_that("renv.ignore=FALSE, eval=TRUE is handled", {
  deps <- dependencies("resources/ignore.Rmd")
  expect_true("A" %in% deps$Package)
  expect_false("a" %in% deps$Package)
})

test_that("eval=<expr> is treated as truthy", {
  deps <- dependencies("resources/chunk-eval.Rmd", quiet = TRUE)
  expect_true("A" %in% deps$Package)
  expect_false("a" %in% deps$Package)
})

test_that("piped expressions can be parsed for dependencies", {
  deps <- dependencies(renv_tests_path("resources/magrittr.R"))
  expect_setequal(deps$Package, c("A", "B", "C"))
})

test_that("bslib dependencies are discovered", {
  deps <- dependencies("resources/bslib.Rmd")
  expect_true("bslib" %in% deps$Package)
})

test_that("utility script dependencies are discovered", {
  deps <- dependencies("resources/utility")
  expect_false(is.null(deps))
  expect_setequal(deps$Package, c("A", "B"))
})

test_that("we handle shiny_prerendered documents", {
  deps <- dependencies("resources/shiny-prerendered.Rmd")
  expect_true("shiny" %in% deps$Package)
})

test_that("we don't infer a dependency on rmarkdown for empty .qmd", {
  deps <- dependencies("resources/quarto-empty.qmd")
  expect_true(is.null(deps) || !"rmarkdown" %in% deps$Package)
})

test_that("we do infer dependency on rmarkdown for .qmd with R chunks", {
  deps <- dependencies("resources/quarto-r-chunks.qmd")
  expect_true("rmarkdown" %in% deps$Package)
})

test_that("we parse package references from arbitrary yaml fields", {
  deps <- dependencies("resources/rmd-base-format.Rmd")
  expect_true("bookdown" %in% deps$Package)
  expect_true("rticles" %in% deps$Package)
})

test_that("dependencies in parameterized documents are discovered", {
  deps <- dependencies(test_path("resources/params.Rmd"))
  expect_true(all(c("shiny", "A") %in% deps$Package))
  expect_false("B" %in% deps$Package)
})

test_that("we ignore chunks with '#| eval: false'", {
  deps <- dependencies("resources/yaml-chunks.Rmd")
  expect_false("a" %in% deps$Package)
  expect_true("A" %in% deps$Package)
})

test_that("dependencies in hidden folders are not scoured", {
  renv_tests_scope()

  dir.create(".hidden")
  writeLines("library(A)", con = ".hidden/deps.R")

  deps <- dependencies()
  expect_false("A" %in% deps$Package)

  writeLines("!.hidden", con = ".renvignore")
  deps <- dependencies()
  expect_true("A" %in% deps$Package)

})

test_that("dependencies() doesn't barf on files without read permission", {

  skip_on_cran()
  skip_on_windows()
  renv_tests_scope()

  dir.create("secrets")
  writeLines("library(dplyr)", con = "secrets/secrets.R")
  Sys.chmod("secrets/secrets.R", mode = "0000")

  expect_error(renv_file_read("secrets/secrets.R"))
  deps <- dependencies()
  expect_true(NROW(deps) == 0L)

})

test_that("dependencies() doesn't barf on malformed DESCRIPTION files", {

  skip_on_windows()
  renv_tests_scope()

  writeLines("Depends: A, B\n\nImports: C, D", con = "DESCRIPTION")
  deps <- dependencies()
  expect_setequal(deps$Package, c("A", "B", "C", "D"))

})

test_that("dependencies() handles inline YAML comments", {
  deps <- dependencies("resources/chunk-yaml.Rmd")
  expect_true("A" %in% deps$Package)
})

test_that("we can parse remotes from a DESCRIPTION file", {

  desc <- heredoc('
    Remotes: r-dbi/DBItest
  ')

  descfile <- renv_scope_tempfile()
  writeLines(desc, con = descfile)
  deps <- renv_dependencies_discover_description(descfile, fields = "Remotes")
  expect_equal(deps$Package, "r-dbi/DBItest")

})

test_that("dependencies ignore pseudo-code in YAML metadata", {
  path <- renv_scope_tempfile()
  writeLines(con = path, c(
    '---',
    'title: "RStudio::conf reflections"',
    '---',
    '',
    'Hello!'
  ))

  deps <- renv_dependencies_discover_rmd_yaml_header(path, "rmd")
  expect_equal(deps$Package, "rmarkdown")
})

test_that("~/.Rprofile included in dev dependencies when config$user.profile()", {
  path <- renv_scope_tempfile("renv-profile", fileext = ".R")
  writeLines("library(utils)", path)
  renv_scope_envvars(R_PROFILE_USER = normalizePath(path, winslash = "/"))
  renv_scope_options(renv.config.user.profile = TRUE)

  renv_tests_scope()
  deps <- renv_dependencies_impl(dev = TRUE)
  expect_equal(deps$Package, "utils")
  expect_equal(deps$Dev, TRUE)
})

test_that("captures dependencies from Jupyter notebooks", {

  path <- test_path("resources/notebook.ipynb")
  deps <- dependencies(path)
  expect_setequal(deps$Package, c("IRkernel", "MASS", "stats"))
  expect_equal(deps$Source, rep(renv_path_normalize(path), 3))

})

test_that("we tolerate calls when parsing dependencies", {

  document <- heredoc('
    ```{r, renv.ignore=TRUE || TRUE}
    library(A)
    ```

    ```{r, renv.ignore=FALSE && TRUE}
    library(B)
    ```
  ')

  file <- renv_scope_tempfile("renv-test-", fileext = ".Rmd")
  writeLines(document, con = file)

  deps <- dependencies(file)
  expect_false("A" %in% deps$Package)
  expect_true("B" %in% deps$Package)

})

test_that("dependencies() notifies the user if directories contain lots of files", {
  project <- renv_tests_scope()
  init()

  # create data directory with 'lots' of files
  dir.create("data")
  setwd("data")
  files <- sprintf("%03i.R", 1:200)
  file.create(files)
  setwd("..")

  # try to collect snapshot dependencies
  renv_scope_options(renv.dependencies.elapsed_time_threshold = 0)
  expect_snapshot(. <- renv_snapshot_dependencies(project))

})

test_that("dependencies() can parse NAMESPACE files", {

  project <- renv_tests_scope()
  desc <- heredoc("
    Type: Package
    Package: test
    Version: 0.1.0
  ")
  writeLines(desc, con = "DESCRIPTION")

  namespace <- heredoc("
    import(utils)
    importFrom(tools, SIGQUIT)
    import(graphics, except = c(abline))
  ")
  writeLines(namespace, con = "NAMESPACE")

  deps <- dependencies()
  expect_setequal(deps$Package, c("graphics", "tools", "utils"))

})

test_that("dependencies() handles upper-case engine names", {

  document <- heredoc("
    ```{R}
    library(A)
    ```
  ")

  file <- renv_scope_tempfile(fileext = ".Rmd")
  writeLines(document, con = file)
  deps <- dependencies(file, quiet = TRUE)
  expect_true("A" %in% deps$Package)

})

test_that("dependencies() ignores R when specified in a DESCRIPTION file", {

  project <- renv_tests_scope()
  desc <- heredoc("
    Type: Package
    Package: test
    Version: 0.1.0
    Depends: R (>= 4.0.0)
  ")
  writeLines(desc, con = "DESCRIPTION")

  deps <- dependencies(quiet = TRUE)
  expect_false("R" %in% deps$Package)

})

test_that("dependencies() with different extensions", {

  project <- renv_tests_scope()

  writeLines("library(A)", con = "a.R")
  writeLines("```{r}\nlibrary(B)\n```", con = "a.Rmd")

  deps <- dependencies(quiet = TRUE)
  expect_true("A" %in% deps$Package)
  expect_true("B" %in% deps$Package)

})

test_that("dependencies() can infer an svglite dependency from ggsave", {

  document <- heredoc('
    library(ggplot2)
    ggsave(filename = "test.svg")
  ')

  file <- renv_scope_tempfile("renv-test-", fileext = ".R")
  writeLines(document, con = file)

  deps <- dependencies(file, quiet = TRUE)
  expect_contains(deps$Package, "svglite")

})

test_that("dependencies() can handle calls", {

  document <- heredoc('
    ```{r}
    #| eval = c(1, 2)
    ```
  ')

  file <- renv_scope_tempfile("renv-test-", fileext = ".Rmd")
  writeLines(document, con = file)

  expect_no_warning(
    dependencies(file, quiet = TRUE)
  )

})

test_that("dependencies() detects usages of Junit test reporters", {

  check <- function(document) {
    file <- renv_scope_tempfile("renv-test-", fileext = ".R")
    writeLines(document, con = file)
    deps <- dependencies(file, quiet = TRUE)
    expect_contains(deps$Package, "xml2")
  }

  check("JunitReporterMock <- R6::R6Class(\"JunitReporterMock\", inherit = JunitReporter)")
  check("JunitReporter$new()")
  check("testthat::test_dir(reporter = JunitReporter)")
  check("testthat::test_dir(reporter = \"junit\")")

})

test_that("dependencies() detects usage of ragg_png device", {

  check <- function(document) {

    file <- renv_scope_tempfile("renv-test-", fileext = ".R")
    writeLines(document, con = file)

    deps <- dependencies(file, quiet = TRUE)
    expect_contains(deps$Package, "ragg")
  }

  check("opts_chunk$set(dev = \"ragg_png\")")
  check("knitr::opts_chunk$set(dev = \"ragg_png\")")

})

test_that("dependencies() does not create 'object' in parent environment", {
  result <- dependencies("resources/code.R", quiet = TRUE)
  expect_false(exists("object", envir = environment(), inherits = FALSE))
})

test_that("R scripts that appear destined for knitr::spin() are detected", {
  result <- dependencies("resources/knitr-spin.R", quiet = TRUE)
  expect_contains(result$Package, c("knitr", "rmarkdown"))
})

test_that("renv infers a dev. dependency on lintr", {
  project <- renv_tests_scope()
  file.create(".lintr")
  deps <- dependencies(quiet = TRUE, dev = TRUE)
  expect_contains(deps$Package, "lintr")
})

test_that("https://github.com/rstudio/renv/issues/2052", {

  renv_scope_tempdir()
  dir.create("subdir")
  writeLines("library(A)", con = "subdir/test.R")
  writeLines(c("*", "!/**/", "!*.*"), con = ".renvignore")
  deps <- dependencies(quiet = TRUE, root = getwd())
  expect_contains(deps$Package, "A")

})

test_that("https://github.com/rstudio/renv/issues/2047", {
  renv_tests_scope()
  writeLines("citation(\"breakfast\")", con = "_deps.R")
  init()
  expect_true(renv_package_installed("breakfast"))
})

test_that("https://github.com/rstudio/renv/issues/2110", {
  renv_tests_scope()
  writeLines("library()", con = "_deps.R")
  deps <- dependencies(quiet = TRUE, root = getwd())
  expect_equal(nrow(deps), 0L)
})

test_that("documents with empty YAML headers are handled", {
  path <- renv_tests_path("resources/empty-yaml-header.Rmd")
  result <- dependencies(path, quiet = TRUE)
  expect_equal(result$Package, "rmarkdown")
})

test_that("unexpected Sweave chunk options are handled", {
  path <- renv_tests_path("resources/result-equal-hide.Rnw")
  result <- dependencies(path, quiet = TRUE)
})
