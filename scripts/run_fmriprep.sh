#!/bin/bash

# Make sure that the fmriprep-docker wrapper is installed in your venv
# and that the venv is activated

# ⚠️ run this script in the background using the following ⚠️
# nohup ./run_fmriprep.sh >> fmriprep.log 2>&1 &


# ── Specify desired paths ───────────────────────────────────────
bids_root="/data03/MRI_hackaton_data/Data_collection/bids"
deriv_root="/data03/MRI_hackaton_data/Data_collection/fmriprep"
work_dir="./fmriprep_work_MASSIVE_DELETE_ASAP"


# ── Do not touch anything below! ────────────────────────────────

if [ -t 1 ]; then
    echo ""
    echo "  ⚠️  Do not run this script directly."
    echo "  fMRIprep is a long-running job. Launch it in the background:"
    echo ""
    echo "      nohup ./run_fmriprep.sh >> fmriprep.log 2>&1 &"
    echo ""
    echo "  Then monitor with:  tail -f fmriprep.log"
    echo ""
    exit 1
fi


# Create the work_dir so that docker can work in it and the user
# can remove it once fmriprep has finished
[ ! -d ${work_dir} ] && mkdir -p ${work_dir}


# ── FreeSurfer license ─────────────────────────────────────────────────────
# Some users may not have FREESURFER_HOME set in their environment
FREESURFER_HOME="/usr/local/freesurfer"


# ── Parallelism ────────────────────────────────────────────────────────────
# Number of CPU cores for this fmriprep call.
# If N people run fmriprep simultaneously: nprocs ≈ total_cores / N
# Storm has 32 cores; with 4 people running at once, use nprocs=7 or 8.
nprocs=7


echo "=== fMRIprep started: $(date) ==="

# ── Run fMRIprep ───────────────────────────────────────────────────────────
fmriprep-docker \
    ${bids_root} \
    ${deriv_root} \
    participant \
    -u $(id -u):$(id -g) \
    --no-tty \
    --fs-no-reconall \
    --fs-license-file ${FREESURFER_HOME}/license.txt \
    --output-spaces MNI152NLin2009cAsym:res-2 \
    --fd-spike-threshold 0.5 \
    --dvars-spike-threshold 1.5 \
    --ignore slicetiming \
    --nprocs ${nprocs} \
    --write-graph \
    --notrack \
    -w ${work_dir}

    

echo "=== fMRIprep finished: $(date) ==="
