#!/bin/bash

export FWHM=6          # desired smoothing kernel in mm
export n_parallel=10
export deriv_dir="/data03/MRI_hackaton_data/Data_collection/fmriprep"
list_subj="/data00/MRI_hackaton/scripts/list_subj.txt"

xargs -a "${list_subj}" -n1 -P${n_parallel} -I{} bash -c '
    sub="{}"
    echo "=== ${sub}: smoothing ==="
    for f in $(find "${deriv_dir}/${sub}" -name "*_desc-scaled_bold.nii.gz" | sort); do
        in_dir=$(dirname "${f}")

        fslmaths ${f} -Tmean "${f/_desc-scaled_bold.nii.gz/_desc-brain_mask.nii.gz}"
        mask="${f/_desc-scaled_bold.nii.gz/_desc-brain_mask.nii.gz}"
        out="${f/_desc-scaled_bold.nii.gz/_desc-smoothed_bold.nii.gz}"

        docker run --rm \
            -e OMP_NUM_THREADS=2 \
            -v "${in_dir}:${in_dir}" \
            afni/afni_make_build \
            3dBlurToFWHM \
                -input  "${f}" \
                -FWHM   ${FWHM} \
                -mask   ${mask} \
                -prefix "${out}"
        echo "  Smoothed: $(basename ${out})"
    done
'
