# fmri_denoiser.R — Shiny app for confound selection + fsl_regfilt script generation
#
# See procedures/fmri_denoiser.md for full design documentation.
#
# Usage
# -----
# Launch from an R session:
#   shiny::runApp("scripts/fmri_denoiser.R", port = 3838)
#
# Or from the terminal (keeps running after SSH disconnect if in tmux/nohup):
#   Rscript -e "shiny::runApp('scripts/fmri_denoiser.R', port=3838, host='0.0.0.0')"
#
# SSH tunnel (from your laptop):
#   ssh -L 3838:localhost:3838 yourname@storm
#   Then open http://localhost:3838

library(shiny)
library(shinyFiles)
library(DT)
library(dplyr)
library(readr)
library(tidyr)
library(stringr)
library(jsonlite)
library(pheatmap)

# ═══════════════════════════════════════════════════════════════════════════════
# Utility functions
# ═══════════════════════════════════════════════════════════════════════════════

# Extract BIDS entity prefix from a filename
# e.g. "sub-001_ses-01_task-rest_run-1_space-MNI..._bold.nii.gz"
#   → "sub-001_ses-01_task-rest_run-1"
get_bids_prefix <- function(fname) {
  entities <- str_extract_all(
    basename(fname),
    "(sub|ses|task|run|acq|dir|echo|part)-[^_]+"
  )[[1]]
  paste(entities, collapse = "_")
}

# Discover all fmriprep preprocessed BOLD files
discover_bolds <- function(deriv_dir) {
  paths <- list.files(
    deriv_dir,
    pattern   = "_desc-preproc_bold\\.nii\\.gz$",
    recursive = TRUE,
    full.names = TRUE
  )
  if (length(paths) == 0) {
    return(tibble(path = character(), sub = character(), task = character()))
  }
  tibble(path = paths) |>
    mutate(
      sub  = str_extract(basename(path), "sub-[^_]+"),
      task = str_extract(basename(path), "(?<=task-)[^_]+")
    )
}

# Summarise BOLDs by task (for Column 1 table)
get_task_summary <- function(bold_df) {
  bold_df |>
    group_by(task) |>
    summarise(`BOLD files` = n(), .groups = "drop") |>
    arrange(task) |>
    rename(Task = task)
}

# Discover confound TSV patterns in the derivatives folder.
# "Pattern" = the filename suffix after the BIDS entity prefix.
# e.g. "_desc-confounds_timeseries.tsv"
#      "_space-MNI152NLin2009cAsym_res-2_desc-cosine180s_confounds.tsv"
discover_tsv_patterns <- function(deriv_dir) {
  all_fnames <- basename(list.files(
    deriv_dir,
    pattern   = "\\.tsv$",
    recursive = TRUE
  ))
  if (length(all_fnames) == 0) return(tibble())

  suffixes <- sapply(all_fnames, function(fname) {
    prefix <- get_bids_prefix(fname)
    if (nchar(prefix) == 0) return(NA_character_)
    str_remove(fname, paste0("^", fixed(prefix)))
  })

  tibble(Pattern = suffixes) |>
    filter(
      !is.na(Pattern),
      str_detect(Pattern, "confounds|timeseries")   # keep only confound-like TSVs
    ) |>
    count(Pattern, name = "Files found") |>
    arrange(Pattern)
}

# Find the TSV file for a given BOLD path + suffix pattern
# e.g. bold="...sub-001_ses-01_task-rest_bold.nii.gz", suffix="_desc-confounds_timeseries.tsv"
#   → "...sub-001_ses-01_task-rest_desc-confounds_timeseries.tsv"
get_tsv_for_bold <- function(bold_path, tsv_suffix) {
  bold_dir    <- dirname(bold_path)
  bold_prefix <- get_bids_prefix(basename(bold_path))
  expected    <- file.path(bold_dir, paste0(bold_prefix, tsv_suffix))
  if (file.exists(expected)) expected else NA_character_
}

# Collect all column names from the TSVs of the first available subject
get_all_columns <- function(bold_df, selected_tasks, tsv_suffixes) {
  first_sub <- bold_df |>
    filter(task %in% selected_tasks) |>
    pull(sub) |> unique() |> first()

  target_bolds <- bold_df |>
    filter(task %in% selected_tasks, sub == first_sub) |>
    pull(path)

  all_cols <- character()
  for (bold_path in target_bolds) {
    for (sfx in tsv_suffixes) {
      tsv_path <- get_tsv_for_bold(bold_path, sfx)
      if (!is.na(tsv_path)) {
        cols     <- names(read_tsv(tsv_path, n_max = 0, show_col_types = FALSE))
        all_cols <- union(all_cols, cols)
      }
    }
  }
  tibble(Column = sort(all_cols))
}

# Build the combined confound data.frame for one BOLD file
build_confound_matrix <- function(bold_path, tsv_suffixes, selected_cols) {
  dfs <- list()
  for (sfx in tsv_suffixes) {
    tsv_path <- get_tsv_for_bold(bold_path, sfx)
    if (!is.na(tsv_path) && file.exists(tsv_path)) {
      df        <- read_tsv(tsv_path, show_col_types = FALSE)
      available <- intersect(selected_cols, names(df))
      if (length(available) > 0) {
        dfs[[length(dfs) + 1]] <- select(df, all_of(available))
      }
    }
  }
  if (length(dfs) == 0) return(NULL)
  bind_cols(dfs) |>
    mutate(across(everything(), as.numeric)) |>   # coerce "n/a" strings → NA
    mutate(across(everything(), ~replace_na(.x, 0)))  # NA → 0
}

# Generate the run_regfilt.sh bash script as a character string
generate_regfilt_script <- function(config, bold_df) {
  subjects <- bold_df |>
    filter(task %in% config$selected_tasks) |>
    pull(sub) |> unique() |> sort()

  # Build the task filter block for bash
  conds <- paste0('"${bold}" != *"_task-', config$selected_tasks, '_"*')
  if (length(conds) == 1) {
    filter_block <- paste0("        [[ ", conds, " ]] && continue")
  } else {
    inner        <- paste(conds, collapse = " && \\\n           ")
    filter_block <- paste0("        [[ \\\n           ", inner, "\n        ]] && continue")
  }

  col_wrapped <- paste(
    strwrap(paste(config$selected_columns, collapse = " "), width = 55),
    collapse = "\n#   "
  )
  pat_lines  <- paste0("#   ", config$confound_tsv_patterns, collapse = "\n")
  subj_lines <- paste0('    "', subjects, '"', collapse = "\n")

  lines <- c(
    "#!/bin/bash",
    "# ============================================================",
    "# Confound regression with fsl_regfilt",
    paste0("# Generated by fMRI Denoiser app — ", format(Sys.time(), "%Y-%m-%d %H:%M")),
    "# ============================================================",
    "#",
    paste0("# Derivatives : ", config$deriv_dir),
    paste0("# Tasks       : ", paste(config$selected_tasks, collapse = ", ")),
    paste0("# Subjects    : ", length(subjects)),
    "#",
    "# Confound files used (pre-built by the app):",
    pat_lines,
    "#",
    paste0("# Selected regressors (", length(config$selected_columns), " total):"),
    paste0("#   ", col_wrapped),
    "#",
    "# NOTE: Confound .txt files were pre-built by the app.",
    "# Re-run the app if you want to change the confound selection.",
    "#",
    "# To run:",
    "#   nohup bash run_regfilt.sh > run_regfilt.log 2>&1 &",
    "# ============================================================",
    "",
    paste0('deriv_dir="', config$deriv_dir, '"'),
    paste0("n_parallel=", config$n_parallel),
    "",
    "# ── Per-subject processing ─────────────────────────────────────────────────",
    "process_subject() {",
    '    local sub="$1"',
    '    echo "=== ${sub}: started ==="',
    "",
    '    for bold in $(find "${deriv_dir}/${sub}" -name "*_desc-preproc_bold.nii.gz" | sort); do',
    "",
    "        # Keep only selected tasks (all runs included automatically)",
    filter_block,
    "",
    '        local confounds="${bold/_desc-preproc_bold.nii.gz/_desc-selected_confounds.txt}"',
    '        local output="${bold/_desc-preproc_bold.nii.gz/_desc-denoised_bold.nii.gz}"',
    '        local n_cols=$(awk "NR==1{print NF}" "${confounds}")',
    '        local indices=$(seq 1 ${n_cols} | paste -sd,)',
    "",
    '        echo "  ${sub}: $(basename ${bold})"',
    "        fsl_regfilt \\",
    '            -i "${bold}" \\',
    '            -d "${confounds}" \\',
    '            -f "${indices}" \\',
    '            -o "${output}"',
    "    done",
    "",
    '    echo "=== ${sub}: done ==="',
    "}",
    "export -f process_subject",
    "export deriv_dir",
    "",
    "# ── Subjects to process ────────────────────────────────────────────────────",
    "subjects=(",
    subj_lines,
    ")",
    "",
    "printf '%s\\n' \"${subjects[@]}\" | xargs -n1 -P${n_parallel} -I{} bash -c 'process_subject {}'"
  )

  paste(lines, collapse = "\n")
}


# ═══════════════════════════════════════════════════════════════════════════════
# UI
# ═══════════════════════════════════════════════════════════════════════════════

ui <- fluidPage(

  # titlePanel("fMRI Denoiser — Confound Selection & fsl_regfilt"),

  # tags$head(
  #   # Import the font from Google
  #   tags$link(
  #     href = "https://fonts.googleapis.com/css2?family=Raleway&display=swap",
  #     rel  = "stylesheet"
  #   ),
  #   # Apply it (add this alongside the existing .well / h5 style block)
  #   tags$style(HTML("
  #     * { font-family: 'Raleway', sans-serif !important; }
  #   "))
  # ),

  titlePanel(
    div(
      h3("fMRI Denoiser — Confound Selection & fsl_regfilt"),
      h5("LeonardoC 2026-04-17", style = "color: gray; font-weight: normal;font-style: italic;")
    )
  ),

  tags$head(tags$style(HTML("
    .well { padding: 12px; }
    h5 { color: #495057; margin-top: 10px; margin-bottom: 4px; }
    .btn { margin: 2px; }
  "))),

  fluidRow(

    # ── Column 1: Discovery ──────────────────────────────────────────────────
    column(3,
      wellPanel(
        h4("① Discovery"),

        h5("Derivatives folder (fmriprep)"),
        shinyDirButton("deriv_dir", "Browse server…",
                       title = "Select fmriprep derivatives folder"),
        br(),
        textOutput("deriv_dir_text"),
        hr(),

        h5("Output folder"),
        tags$small("Config JSON + run_regfilt.sh will be saved here"),
        br(),
        shinyDirButton("output_dir", "Browse server…",
                       title = "Select output folder"),
        br(),
        textOutput("output_dir_text"),
        hr(),

        h5("Tasks found"),
        tags$small("Select tasks to process"),
        DTOutput("task_table"),
        br(),

        h5("Confound TSV files found"),
        tags$small("Select TSV types to include"),
        DTOutput("tsv_table")
      )
    ),

    # ── Column 2: Confound selection ─────────────────────────────────────────
    column(5,
      wellPanel(
        h4("② Confound selection"),

        h5("Available columns"),
        tags$small(
          "Columns found in the selected TSVs (first subject shown). ",
          "Select the regressors to include."
        ),
        DTOutput("columns_table"),
        br(),

        fluidRow(
          column(4,
            numericInput("n_parallel", "Parallel subjects",
                         value = 5, min = 1, max = 32, step = 1)
          ),
          column(4,
            textInput("flavour", "Flavour",
                      placeholder = "optional",
                      value = "")
          )
        ),
        br(),

        fluidRow(
          column(4,
            actionButton("save_config", "💾 Save config",
                         class = "btn-primary", width = "100%")
          ),
          column(4,
            shinyFilesButton("load_config", "📂 Load config",
                             title  = "Select denoising_config.json",
                             multiple = FALSE)
          ),
          column(4,
            actionButton("generate", "▶ Generate",
                         class = "btn-success", width = "100%")
          )
        ),
        br(),

        h5("Status"),
        verbatimTextOutput("status_msg")
      )
    ),

    # ── Column 3: QA heatmap ─────────────────────────────────────────────────
    column(4,
      wellPanel(
        h4("③ Confound correlation QA"),
        tags$small(
          "Correlation matrix of selected regressors (first available subject). ",
          "Use this to spot multicollinearity before running the regression."
        ),
        br(), br(),
        plotOutput("heatmap", height = "560px")
      )
    )

  ) # fluidRow
) # fluidPage


# ═══════════════════════════════════════════════════════════════════════════════
# Server
# ═══════════════════════════════════════════════════════════════════════════════

server <- function(input, output, session) {

  # File system root: start at "/" so any server path is reachable
  volumes <- c(Root = "/")

  shinyDirChoose(input, "deriv_dir",  roots = volumes, session = session)
  shinyDirChoose(input, "output_dir", roots = volumes, session = session)

  # ── Reactive state ─────────────────────────────────────────────────────────
  rv <- reactiveValues(
    deriv_path         = NULL,
    output_path        = NULL,
    bold_df            = NULL,
    tsv_patterns_df    = NULL,
    pending_col_select = character()   # used to restore column selection on load
  )

  # Load config browser — starts at "/"; updates to add Config folder shortcut once output_dir is set
  shinyFileChoose(input, "load_config", roots = volumes, session = session,
                  filetypes = "json")

  observeEvent(rv$output_path, {
    req(rv$output_path)
    shinyFileChoose(
      input, "load_config",
      roots     = c("Config folder" = rv$output_path, Root = "/"),
      session   = session,
      filetypes = "json"
    )
  })

  # Helper: current roots for load_config (must match what shinyFileChoose used)
  load_config_roots <- reactive({
    if (!is.null(rv$output_path))
      c("Config folder" = rv$output_path, Root = "/")
    else
      c(Root = "/")
  })

  # ── Derivatives folder ─────────────────────────────────────────────────────
  observeEvent(input$deriv_dir, {
    req(is.list(input$deriv_dir))
    rv$deriv_path <- parseDirPath(volumes, input$deriv_dir)

    withProgress(message = "Scanning for BOLD and TSV files…", {
      rv$bold_df         <- discover_bolds(rv$deriv_path)
      rv$tsv_patterns_df <- discover_tsv_patterns(rv$deriv_path)
    })
  })

  output$deriv_dir_text <- renderText({
    if (is.null(rv$deriv_path)) "— not selected —" else rv$deriv_path
  })

  # ── Output folder ──────────────────────────────────────────────────────────
  observeEvent(input$output_dir, {
    req(is.list(input$output_dir))
    rv$output_path <- parseDirPath(volumes, input$output_dir)
  })

  output$output_dir_text <- renderText({
    if (is.null(rv$output_path)) "— not selected —" else rv$output_path
  })

  # ── Task table (Column 1) ──────────────────────────────────────────────────
  task_summary_df <- reactive({
    req(rv$bold_df, nrow(rv$bold_df) > 0)
    get_task_summary(rv$bold_df)
  })

  output$task_table <- renderDT({
    df <- task_summary_df()
    datatable(
      df,
      selection = list(mode = "multiple",
                       selected = seq_len(nrow(df))),   # all pre-selected
      options   = list(dom = "t", pageLength = 50),
      rownames  = FALSE
    )
  })

  selected_tasks <- reactive({
    df  <- task_summary_df()
    idx <- input$task_table_rows_selected
    if (length(idx) == 0) return(character())
    df$Task[idx]
  })

  # ── TSV patterns table (Column 1) ─────────────────────────────────────────
  output$tsv_table <- renderDT({
    req(rv$tsv_patterns_df, nrow(rv$tsv_patterns_df) > 0)
    df <- rv$tsv_patterns_df
    datatable(
      df,
      selection = list(mode = "multiple",
                       selected = seq_len(nrow(df))),   # all pre-selected
      options   = list(dom = "t", pageLength = 20),
      rownames  = FALSE
    )
  })

  selected_tsv_suffixes <- reactive({
    req(rv$tsv_patterns_df, nrow(rv$tsv_patterns_df) > 0)
    idx <- input$tsv_table_rows_selected
    if (length(idx) == 0) return(character())
    rv$tsv_patterns_df$Pattern[idx]
  })

  # ── Confound columns table (Column 2) ─────────────────────────────────────
  columns_df <- reactive({
    tasks    <- selected_tasks()
    suffixes <- selected_tsv_suffixes()
    req(rv$bold_df, length(tasks) > 0, length(suffixes) > 0)
    withProgress(message = "Reading column names…",
      get_all_columns(rv$bold_df, tasks, suffixes)
    )
  })

  output$columns_table <- renderDT({
    df <- columns_df()
    req(nrow(df) > 0)
    datatable(
      df,
      selection = list(mode = "multiple"),
      options   = list(dom = "ftp", pageLength = 15, scrollY = "320px"),
      rownames  = FALSE
    )
  })

  selected_columns <- reactive({
    df  <- columns_df()
    idx <- input$columns_table_rows_selected
    req(nrow(df) > 0, length(idx) > 0)
    df$Column[idx]
  })

  # ── Apply pending column selection after load_config ──────────────────────
  observeEvent(columns_df(), {
    pending <- rv$pending_col_select
    if (length(pending) == 0) return()
    df  <- columns_df()
    idx <- which(df$Column %in% pending)
    selectRows(dataTableProxy("columns_table"), idx)
    rv$pending_col_select <- character()
  })

  # ── Heatmap (Column 3) ────────────────────────────────────────────────────
  output$heatmap <- renderPlot({
    cols     <- selected_columns()
    tasks    <- selected_tasks()
    suffixes <- selected_tsv_suffixes()
    req(rv$bold_df, length(cols) >= 2, length(tasks) > 0, length(suffixes) > 0)

    first_bold <- rv$bold_df |> filter(task %in% tasks) |> slice(1) |> pull(path)
    mat        <- build_confound_matrix(first_bold, suffixes, cols)
    req(!is.null(mat), ncol(mat) >= 2)

    corr <- cor(mat, use = "pairwise.complete.obs")
    pheatmap(
      corr,
      color          = colorRampPalette(c("#2166ac", "white", "#d6604d"))(100),
      breaks         = seq(-1, 1, length.out = 101),
      fontsize       = 7,
      treeheight_row = 15,
      treeheight_col = 15,
      main           = paste0(length(cols), " regressors  |  first subject preview")
    )
  })

  # ── Save config ────────────────────────────────────────────────────────────
  observeEvent(input$save_config, {
    req(rv$output_path, rv$deriv_path, rv$bold_df)
    tasks    <- selected_tasks()
    suffixes <- selected_tsv_suffixes()
    cols     <- selected_columns()
    req(length(tasks) > 0, length(cols) > 0)

    subjects <- rv$bold_df |>
      filter(task %in% tasks) |>
      pull(sub) |> unique() |> sort()

    config <- list(
      generated             = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
      deriv_dir             = rv$deriv_path,
      output_dir            = rv$output_path,
      selected_tasks        = tasks,
      confound_tsv_patterns = suffixes,
      selected_columns      = cols,
      n_parallel            = input$n_parallel,
      n_subjects            = length(subjects),
      n_confound_regressors = length(cols),
      subjects              = subjects
    )

    flav        <- if (nzchar(trimws(input$flavour))) paste0("_", trimws(input$flavour)) else ""
    config_path <- file.path(rv$output_path, paste0("denoising_config", flav, ".json"))
    write_json(config, config_path, pretty = TRUE, auto_unbox = TRUE)

    output$status_msg <- renderText(paste0("✓ Config saved:\n  ", config_path))
  })

  # ── Load config ────────────────────────────────────────────────────────────
  observeEvent(input$load_config, {
    req(is.list(input$load_config))
    finfo <- parseFilePaths(load_config_roots(), input$load_config)
    req(nrow(finfo) > 0)
    config_path <- as.character(finfo$datapath)
    req(file.exists(config_path))

    config <- read_json(config_path, simplifyVector = TRUE)

    # Restore paths and rescan
    rv$deriv_path  <- config$deriv_dir
    rv$output_path <- config$output_dir

    withProgress(message = "Rescanning…", {
      rv$bold_df         <- discover_bolds(rv$deriv_path)
      rv$tsv_patterns_df <- discover_tsv_patterns(rv$deriv_path)
    })

    # Restore task table selection
    tsum    <- get_task_summary(rv$bold_df)
    t_idx   <- which(tsum$Task %in% config$selected_tasks)
    selectRows(dataTableProxy("task_table"), t_idx)

    # Restore TSV patterns selection
    p_idx   <- which(rv$tsv_patterns_df$Pattern %in% config$confound_tsv_patterns)
    selectRows(dataTableProxy("tsv_table"), p_idx)

    # Store columns to restore — will be applied when columns_df() recomputes
    rv$pending_col_select <- config$selected_columns

    updateNumericInput(session, "n_parallel", value = config$n_parallel)

    output$status_msg <- renderText(paste0(
      "✓ Config loaded:\n  ", config_path,
      "\n\n  Tasks    : ", paste(config$selected_tasks, collapse = ", "),
      "\n  TSV types: ", length(config$confound_tsv_patterns),
      "\n  Columns  : ", length(config$selected_columns), " regressors"
    ))
  })

  # ── Generate outputs ───────────────────────────────────────────────────────
  observeEvent(input$generate, {
    req(rv$bold_df, rv$output_path, rv$deriv_path)
    tasks    <- selected_tasks()
    suffixes <- selected_tsv_suffixes()
    cols     <- selected_columns()
    req(length(tasks) > 0, length(suffixes) > 0, length(cols) > 0)

    flav         <- if (nzchar(trimws(input$flavour))) paste0("_", trimws(input$flavour)) else ""
    target_bolds <- rv$bold_df |> filter(task %in% tasks) |> pull(path)
    n_total      <- length(target_bolds)
    n_done       <- 0
    n_fail       <- 0
    failed       <- character()
    written      <- character()   # accumulate full paths for status log

    # 1. Write per-BOLD confound .txt files
    withProgress(message = "Building confound matrices…", value = 0, {
      for (bold_path in target_bolds) {
        incProgress(1 / n_total, detail = basename(bold_path))  # live progress bar update
        mat <- build_confound_matrix(bold_path, suffixes, cols)
        if (!is.null(mat) && ncol(mat) > 0) {
          out_path <- str_replace(
            bold_path,
            "_desc-preproc_bold\\.nii\\.gz$",
            "_desc-selected_confounds.txt"
          )
          write_delim(mat, out_path, delim = " ", col_names = FALSE, progress = FALSE)
          csv_path <- str_replace(
            bold_path,
            "_desc-preproc_bold\\.nii\\.gz$",
            "_desc-selected_confounds.csv"
          )
          write_csv(mat, csv_path, progress = FALSE)
          written <- c(written, out_path)
          n_done  <- n_done + 1
        } else {
          n_fail <- n_fail + 1
          failed <- c(failed, basename(bold_path))
        }
      }
    })

    # 2. Generate and write run_regfilt.sh (with optional flavour suffix)
    config <- list(
      deriv_dir             = rv$deriv_path,
      selected_tasks        = tasks,
      confound_tsv_patterns = suffixes,
      selected_columns      = cols,
      n_parallel            = input$n_parallel
    )
    script      <- generate_regfilt_script(config, rv$bold_df)
    script_path <- file.path(rv$output_path, paste0("run_regfilt", flav, ".sh"))
    writeLines(script, script_path)

    status <- paste0(
      "✓ Confound matrices: ", n_done, " / ", n_total, " written",
      if (n_fail > 0) paste0("\n  ⚠ Failed (", n_fail, "):\n  ",
                              paste(failed, collapse = "\n  ")) else "",
      "\n\nFiles written:\n  ", paste(written, collapse = "\n  "),
      "\n\n✓ Script saved:\n  ", script_path,
      "\n\nTo run:\n  nohup bash ", script_path, " > run_regfilt.log 2>&1 &"
    )
    output$status_msg <- renderText(status)
  })

} # server

shinyApp(ui, server)
