# ICA Aroma

- [github repo](https://github.com/maartenmennes/ICA-AROMA)
- [manual in pdf](https://github.com/maartenmennes/ICA-AROMA/blob/master/Manual.pdf)
- note that differently from what written in the manual, ICA Aroma now uses python 3

ICA Aroma is optimized to work together with the other procedures in the fsl suite, and in particular with Feat preprocessing (MCFLIRT and fnirt registration). Therefore we need to reproduce those passages.

The following is a schematic view of what needs to be run.

```bash
# 0. MCFLIRT
mcflirt -in example_func.nii.gz -out mc/example_func_mcf -plots

# 1. Linear registration: functional → T1 (highres)
flirt -in example_func.nii.gz \
      -ref highres_brain.nii.gz \
      -out reg/example_func2highres.nii.gz \
      -omat reg/example_func2highres.mat \
      -dof 6 \
      -cost corratio

# 2. Linear registration: T1 (highres) → MNI (affine)
flirt -in highres_brain.nii.gz \
      -ref $FSLDIR/data/standard/MNI152_T1_2mm_brain.nii.gz \
      -out reg/highres2standard_affine.nii.gz \
      -omat reg/highres2standard_affine.mat \
      -dof 12 \
      -cost corratio

# 3. Nonlinear registration: T1 (highres) → MNI (warp)
fnirt --in=highres.nii.gz \
      --aff=reg/highres2standard_affine.mat \
      --ref=$FSLDIR/data/standard/MNI152_T1_2mm.nii.gz \
      --cout=reg/highres2standard_warp.nii.gz \
      --config=T1_2_MNI152_2mm


# Run aroma
python <path>/ICA_AROMA.py \
    -in mc/example_func_mcf.nii.gz \
    -out ICA_AROMA \
    -mc mc/example_func_mcf.par \
    -affmat reg/example_func2highres.mat \
    -warp reg/highres2standard_warp.nii.gz \
    -m mask_aroma.nii.gz
```

