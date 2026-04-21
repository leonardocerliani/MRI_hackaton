#!/bin/bash

# Make sure that the fmriprep-docker wrapper is installed in your venv
# and that the venv is activated

# ⚠️ run this script in the background using the following ⚠️
# nohup ./run_fmriprep_synthstrip.sh >> fmriprep.log 2>&1 &


# ── Specify desired paths ───────────────────────────────────────
bids_root="/data03/MRI_hackaton_data/Data_collection/bids"
deriv_root="/data03/MRI_hackaton_data/Data_collection/fmriprep_synthstrip"
work_dir="./fmriprep_work_MASSIVE_DELETE_ASAP"


# ── Do not touch anything below! ────────────────────────────────

if [ -t 1 ]; then
    echo ""
    echo "  ⚠️  Do not run this script directly."
    echo "  fMRIprep is a long-running job. Launch it in the background:"
    echo ""
    echo "      nohup ./run_fmriprep_synthstrip.sh >> fmriprep.log 2>&1 &"
    echo ""
    echo "  Then monitor with:  tail -f fmriprep.log"
    echo ""
    exit 1
fi


# Create the work_dir so that docker can work in it and the user
# can remove it once fmriprep has finished
[ ! -d ${work_dir} ] && mkdir -p ${work_dir}


echo "=== Pre-flight: synthstrip check ==="
# ── Pre-flight: replace T1w with synthstrip brain for all subjects ───────────
n_t1w=$(find "${bids_root}" -type f -name '*T1w.nii.gz'            ! -name '*ORIG*' | wc -l)
n_orig=$(find "${bids_root}" -type f -name '*ORIG_T1w_brain.nii.gz'                 | wc -l)

echo "  T1w files (original) : ${n_t1w}"
echo "  ORIG_T1w_brain files : ${n_orig}"

if [ "${n_t1w}" -ne "${n_orig}" ]; then
    echo "  ⚠️  Not all subjects have a synthstrip skull-stripped version of T1w."
    echo "  Run synthstrip first, then re-launch this script."
    exit 1
fi

echo "  ✓ Counts match — copying synthstrip brains over T1w files"
find "${bids_root}" -type f -name '*ORIG_T1w_brain.nii.gz' | while read orig_brain; do
    t1w="${orig_brain/ORIG_T1w_brain.nii.gz/T1w.nii.gz}"
    cp "${orig_brain}" "${t1w}"
    echo "  $(basename ${t1w})"
done
echo "=== Pre-flight done ==="



# ── FreeSurfer license ─────────────────────────────────────────────────────
# Some users may not have FREESURFER_HOME set in their environment
FREESURFER_HOME="/usr/local/freesurfer"


# ── Parallelism ──────────────────────────────────────────────────────
# --nprocs:       workflow-level parallelism (independent nodes at once)
# --omp-nthreads: thread-level parallelism per process (ANTs, ITK)
# Total threads ≈ nprocs × omp-nthreads
nprocs=5
omp_nthreads=3

# ── MNI target resolution 1/2/3 mm ───────────────────────────────────
MNI_res=2


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
    --output-spaces MNI152NLin2009cAsym:res-${MNI_res} \
    --fd-spike-threshold 0.5 \
    --dvars-spike-threshold 1.5 \
    --skull-strip-t1w skip \
    --nprocs ${nprocs} \
    --omp-nthreads ${omp_nthreads} \
    --write-graph \
    --notrack \
    -w ${work_dir}

    

echo "=== fMRIprep finished: $(date) ==="
