#!/bin/bash

# run_smoothing.sh — Configure and launch BOLD smoothing using the smoothing_engine.sh
#
# Edit the parameters section below, then launch in the background:
#   nohup bash run_smoothing.sh >> smoothing.log 2>&1 &
# Monitor with:  tail -f smoothing.log



# ════════════════════════════════════════════════════════════════════════════
# ── User parameters — edit everything in this section ──────────────────────
# ════════════════════════════════════════════════════════════════════════════

export FWHM=6          # desired smoothing kernel in mm
export n_parallel=10
export deriv_dir="/data03/MRI_hackaton_data/Data_collection/fmriprep"
export list_subj="/data00/MRI_hackaton/scripts/list_subj.txt"


# ════════════════════════════════════════════════════════════════════════════
# ── Add one line per task/desc combination to smooth ───────────────────────
# ════════════════════════════════════════════════════════════════════════════

if [ ! -f "${SCRIPT_DIR}/smoothing_engine.sh" ]; then
    echo "⚠️  smoothing_engine.sh not found in ${SCRIPT_DIR}"
    exit 1
fi


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

bash "${SCRIPT_DIR}/smoothing_engine.sh"  emt   preproc_bold
bash "${SCRIPT_DIR}/smoothing_engine.sh"  sddt  scaled_bold

