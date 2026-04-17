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


# ── Parallelism ──────────────────────────────────────────────────────
# --nprocs:       workflow-level parallelism (independent nodes at once)
# --omp-nthreads: thread-level parallelism per process (ANTs, ITK)
# Total threads ≈ nprocs × omp-nthreads
nprocs=5
omp-nthreads=3


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
    --omp-nthreads ${omp_nthreads} \
    --write-graph \
    --notrack \
    -w ${work_dir}

    

echo "=== fMRIprep finished: $(date) ==="
