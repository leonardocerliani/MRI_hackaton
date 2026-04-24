#!/bin/bash

# smoothing_engine.sh — BOLD smoothing engine for one task/desc combination.
#
# Called by run_smoothing.sh — do not run directly.
# All parameters (FWHM, n_parallel, deriv_dir, list_subj) are exported
# by run_smoothing.sh and inherited here and in the xargs subshell.
#
# Usage: bash smoothing_engine.sh <task> <desc>
#   task : BIDS task label, e.g. "emp" or "rest"
#   desc : file descriptor,  e.g. "scaled_bold" or "preproc_bold"

export task="$1"
export desc="$2"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Smoothing  task=${task}  desc=${desc}  FWHM=${FWHM}mm"
echo "════════════════════════════════════════════════════════"

xargs -a "${list_subj}" -n1 -P${n_parallel} -I{} bash -c '
    sub="{}"
    echo "=== ${sub} [task-${task}, desc-${desc}]: started ==="

    for f in $(find "${deriv_dir}/${sub}" -name "*_task-${task}_*_desc-${desc}.nii.gz" | sort); do
        in_dir=$(dirname "${f}")
        mask="${f/_desc-${desc}.nii.gz/_desc-brain_mask.nii.gz}"
        out="${f/_desc-${desc}.nii.gz/_desc-smoothed_bold.nii.gz}"

        fslmaths ${f} -Tmean "${mask}"

        docker run --rm \
            -e OMP_NUM_THREADS=2 \
            -v "${in_dir}:${in_dir}" \
            afni/afni_make_build \
            3dBlurToFWHM \
                -input  "${f}" \
                -FWHM   ${FWHM} \
                -mask   "${mask}" \
                -prefix "${out}"

        echo "  Smoothed: $(basename ${out})"
    done

    echo "=== ${sub} [task-${task}, desc-${desc}]: done ==="
'
