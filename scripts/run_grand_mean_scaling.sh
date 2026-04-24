#!/bin/bash

export deriv_dir="/data03/MRI_hackaton_data/Data_collection/fmriprep"
export flavour="preproc"  # "preproc" or "denoised"


n_parallel=10  # desired number of parallel processes
list_subj="/data00/MRI_hackaton/scripts/list_subj.txt"


xargs -a "${list_subj}" -n1 -P${n_parallel} -I{} bash -c '
    sub="{}"
    echo "=== ${sub}: grand mean scaling ==="
    for f in $(find "${deriv_dir}/${sub}" -name "*_desc-${flavour}_bold.nii.gz" | sort); do
        out="${f/_desc-${flavour}_bold.nii.gz/_desc-scaled_bold.nii.gz}"
        fslmaths "${f}" -ing 10000 "${out}"
    done
'
