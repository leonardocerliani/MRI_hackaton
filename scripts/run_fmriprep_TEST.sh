#!/bin/bash

# run_fmriprep_TEST.sh
#
# TEST version of the fMRIprep launcher — runs fast on a single subject.
#
# Supports three skull-stripping strategies selected by SKULL_STRIP_PROCEDURE:
#
#   "synthstrip"  — use the synthstrip-generated brain (ORIG_T1w_brain)
#                   → copies ORIGINAL_T1W/*_ORIG_T1w_brain.nii.gz → anat/*_T1w.nii.gz
#                   → runs fmriprep with --skull-strip-t1w auto
#
#   "auto"        — use the synthstrip-generated brain (same pre-flight as "synthstrip")
#                   → copies ORIGINAL_T1W/*_ORIG_T1w_brain.nii.gz → anat/*_T1w.nii.gz
#                   → runs fmriprep with --skull-strip-t1w auto
#
#   "fmriprep"    — let fmriprep do its own skull stripping with ANTs
#                   → restores the full-head T1w from ORIGINAL_T1W/*_ORIG_T1w.nii.gz
#                   → runs fmriprep with --skull-strip-t1w force
#
# ⚠️ Do NOT run this script directly — launch in the background: ⚠️
# nohup ./run_fmriprep_TEST.sh >> fmriprep_TEST.log 2>&1 &
# Then monitor with:  tail -f fmriprep_TEST.log


# ════════════════════════════════════════════════════════════════════════════
# ── User parameters — edit everything in this section ──────────────────────
# ════════════════════════════════════════════════════════════════════════════

SKULL_STRIP_PROCEDURE="auto"         # "synthstrip", "auto", or "fmriprep"

bids_root="/data03/MRI_hackaton_data/Data_collection/bids"
deriv_root="/data03/MRI_hackaton_data/Data_collection/fmriprep_synthstrip"
work_dir="./fmriprep_work_MASSIVE_DELETE_ASAP"
list_subj="./list_subj.txt"  # one subject ID per line (e.g. sub-gutsaumc0010)

max_subjects=1                       # number of subjects to process (0 = all)
batch_size=1                         # subjects per fmriprep call

# FreeSurfer
FREESURFER_HOME="/usr/local/freesurfer"
freesurfer_license="${FREESURFER_HOME}/license.txt"

# Parallelism — 32 cores total for a single subject
# --nprocs:       workflow-level parallelism (independent nodes run at once)
# --omp-nthreads: thread-level parallelism per process (ANTs, ITK)
# Total threads ≈ nprocs × omp-nthreads  →  8 × 4 = 32
nprocs=2
omp_nthreads=40

# MNI Template
MNI_template="MNI152NLin2009cAsym:res-2"

# ════════════════════════════════════════════════════════════════════════════
# ── Do not touch anything below! ───────────────────────────────────────────
# ════════════════════════════════════════════════════════════════════════════

if [ -t 1 ]; then
    echo ""
    echo "  ⚠️  Make sure you have adjusted all parameters to your needs."
    echo ""
    echo "  ⚠️  Do not run this script directly."
    echo "  fMRIprep is a long-running job. Launch it in the background:"
    echo ""
    echo "      nohup ./run_fmriprep_TEST.sh >> fmriprep_TEST.log 2>&1 &"
    echo ""
    echo "  Then monitor with:  tail -f fmriprep_TEST.log"
    echo ""
    exit 1
fi


# ── Validate SKULL_STRIP_PROCEDURE ──────────────────────────────────────────
if [ "${SKULL_STRIP_PROCEDURE}" != "synthstrip" ] && \
   [ "${SKULL_STRIP_PROCEDURE}" != "auto" ] && \
   [ "${SKULL_STRIP_PROCEDURE}" != "fmriprep" ]; then
    echo "⚠️  SKULL_STRIP_PROCEDURE must be 'synthstrip', 'auto', or 'fmriprep'."
    echo "    Got: '${SKULL_STRIP_PROCEDURE}'"
    exit 1
fi

# ── Pre-flight: prepare T1w files for all subjects ──────────────────────────
n_t1w=$(find "${bids_root}" -type f -name '*T1w.nii.gz' ! -name '*ORIG*' | wc -l)

if [ "${SKULL_STRIP_PROCEDURE}" = "synthstrip" ] || [ "${SKULL_STRIP_PROCEDURE}" = "auto" ]; then

    echo "=== Pre-flight [${SKULL_STRIP_PROCEDURE}]: brain → T1w ==="
    n_orig=$(find "${bids_root}" -type f -name '*ORIG_T1w_brain.nii.gz' | wc -l)
    echo "  T1w files         : ${n_t1w}"
    echo "  ORIG_T1w_brain    : ${n_orig}"

    if [ "${n_t1w}" -ne "${n_orig}" ]; then
        echo "  ⚠️  Not all subjects have a synthstrip skull-stripped T1w."
        echo "  Run synthstrip first, then re-launch this script."
        exit 1
    fi

    echo "  ✓ Copying synthstrip brains → T1w"
    find "${bids_root}" -type f -name '*ORIG_T1w_brain.nii.gz' | while read src; do
        anat_dir=$(dirname $(dirname "${src}"))    # .../anat/ORIGINAL_T1W → .../anat
        src_name=$(basename "${src}")              # sub-XX_ORIG_T1w_brain.nii.gz
        t1w_name="${src_name/ORIG_T1w_brain/T1w}" # sub-XX_T1w.nii.gz
        cp "${src}" "${anat_dir}/${t1w_name}"
        echo "  ${t1w_name}"
    done

    if [ "${SKULL_STRIP_PROCEDURE}" = "synthstrip" ]; then
        skull_strip_opt="auto"
    else
        skull_strip_opt="auto"
    fi

elif [ "${SKULL_STRIP_PROCEDURE}" = "fmriprep" ]; then

    echo "=== Pre-flight [fmriprep]: full-head T1w → T1w ==="
    n_orig=$(find "${bids_root}" -type f -name '*ORIG_T1w.nii.gz' | wc -l)
    echo "  T1w files         : ${n_t1w}"
    echo "  ORIG_T1w (backup) : ${n_orig}"

    if [ "${n_t1w}" -ne "${n_orig}" ]; then
        echo "  ⚠️  Not all subjects have a full-head T1w backup in ORIGINAL_T1W/."
        echo "  Run synthstrip first (it creates the backup), then re-launch."
        exit 1
    fi

    echo "  ✓ Restoring full-head T1w from backup"
    find "${bids_root}" -type f -name '*ORIG_T1w.nii.gz' | while read src; do
        anat_dir=$(dirname $(dirname "${src}"))  # .../anat/ORIGINAL_T1W → .../anat
        src_name=$(basename "${src}")            # sub-XX_ORIG_T1w.nii.gz
        t1w_name="${src_name/ORIG_T1w/T1w}"     # sub-XX_T1w.nii.gz
        cp "${src}" "${anat_dir}/${t1w_name}"
        echo "  ${t1w_name}"
    done

    skull_strip_opt="force"

fi

echo "=== Pre-flight done — skull_strip_opt: ${skull_strip_opt} ==="


# ── Batch loop ───────────────────────────────────────────────────────────────
mapfile -t all_subjects < "${list_subj}"

# Apply max_subjects limit (0 = process all)
if [ "${max_subjects}" -gt 0 ]; then
    all_subjects=("${all_subjects[@]:0:${max_subjects}}")
fi

n_total=${#all_subjects[@]}
n_batches=$(( (n_total + batch_size - 1) / batch_size ))

echo ""
echo "=== Starting: ${n_total} subjects · ${n_batches} batches of ${batch_size} · $(date) ==="

i=0
batch_num=1

while [ ${i} -lt ${n_total} ]; do

    batch=("${all_subjects[@]:${i}:${batch_size}}")

    echo ""
    echo "─── Batch ${batch_num}/${n_batches} ──────────────────────────────────"
    echo "    Subjects : ${batch[*]}"
    echo "    Started  : $(date)"

    mkdir -p "${work_dir}"

    fmriprep-docker \
        ${bids_root} \
        ${deriv_root} \
        participant \
        -u $(id -u):$(id -g) \
        --participant-label ${batch[@]} \
        --no-tty \
        --fs-no-reconall \
        --fs-license-file ${freesurfer_license} \
        --output-spaces ${MNI_template} \
        --fd-spike-threshold 0.5 \
        --dvars-spike-threshold 1.5 \
        --skull-strip-t1w ${skull_strip_opt} \
        --nprocs ${nprocs} \
        --omp-nthreads ${omp_nthreads} \
        --write-graph \
        --notrack \
        -w ${work_dir}

    echo "    Finished : $(date)"
    echo "    Cleaning : ${work_dir}"
    rm -rf "${work_dir}"

    i=$(( i + batch_size ))
    batch_num=$(( batch_num + 1 ))

done

echo ""
echo "=== All ${n_total} subjects done: $(date) ==="
