# 05. Cosine high-pass filter basis

_LC 2026-04-16_

---

## Rationale

### The problem with sequential filtering + regression

A common preprocessing approach is to apply a temporal high-pass filter to the BOLD data, and then separately regress out nuisance confounds (motion parameters, aCompCor components, etc.). This seems intuitive, but it has a well-documented statistical problem: **sequential application of filtering and regression can reintroduce the very artefacts you tried to remove**, because the two operations are not performed in the same model space (Lindquist et al., 2019, *NeuroImage*).

Specifically:
- If you filter first, the nuisance regressors (which were not filtered) no longer live in the same frequency space as your data → the regression model is mis-specified.
- If you regress first, the filter can "put back" some of the variance you just removed.

### The solution: simultaneous filtering + regression

The correct approach is to include the high-pass filter as **additional regressors** in the same model that contains your motion parameters, aCompCor components, and other confounds — and regress everything out in a single step.

The high-pass filter is represented as a **DCT (Discrete Cosine Transform) basis**: a set of cosine functions of increasing frequency. Including these cosines as nuisance regressors in the model is mathematically equivalent to applying a high-pass filter to the data, but with the critical advantage that it happens simultaneously with all other nuisance regression.

> **In short**: instead of filtering the BOLD time series and then regressing out confounds, you include both the filter basis *and* the confounds in the same regression model, and take the residuals.

This approach is the recommendation of the fMRIprep documentation and is consistent with how SPM implements highpass filtering in GLM analyses.

---

## Why not use fMRIprep's cosine regressors?

fMRIprep does include `cosine_*` columns in its confounds TSV. However, these correspond to a **128-second cutoff** — the cutoff used internally during CompCor estimation. We want a **180-second cutoff**, which is more conservative and commonly used for resting-state and naturalistic (ISC) analyses.

Using a 180-second cutoff removes frequencies slower than:

```
f_c = 1 / 180 ≈ 0.0056 Hz
```

This is appropriate for resting-state and ISC analyses where you want to preserve slower neural fluctuations but remove slow scanner drift and physiological noise.

> **Important**: since fMRIprep computed the aCompCor components after its own 128s high-pass step, there is a small mismatch between the CompCor regressors and our 180s basis. In practice this mismatch is negligible and acceptable. Methods wording: *"CompCor regressors were taken from fMRIprep, while temporal drifts were modeled using a custom 180s DCT basis rather than the 128s cosine terms provided by fMRIprep."*

---

## How many cosine regressors?

The number of basis functions is determined by the run duration and the cutoff:

```
n_basis = floor(2 × run_duration / cutoff_sec)
```

For a typical run of 600 seconds at 180-second cutoff:

```
n_basis = floor(2 × 600 / 180) = floor(6.67) = 6
```

So 6 cosine regressors are needed. The exact number varies by subject if runs have different lengths (e.g., due to scanner aborts). The script handles this automatically by reading the run length from the NIfTI header.

---

## The DCT basis formula

Following SPM's [`spm_dctmtx.m`](https://github.com/spm/spm/blob/main/spm_dctmtx.m):

For `k = 1, 2, ..., n_basis` and timepoint `j = 0, 1, ..., N-1`:

```
X[j, k] = cos( (π / N) × (j + 0.5) × k )
```

where `N` is the total number of volumes. These are zero-mean cosine functions of increasing frequency. Their projection onto the data time series captures and removes the slow fluctuations below the cutoff.

---

## Script: `make_cosine_basis.py`

The script `scripts/make_cosine_basis.py`:
- Takes a preprocessed BOLD NIfTI as input
- Reads TR and N automatically from the NIfTI header (no need to hard-code them)
- Computes the DCT basis for the specified cutoff (default: 180s)
- Saves a TSV file alongside the BOLD, with one column per cosine regressor

### Setup

Make sure the virtual environment is activated and the required packages are installed:

```bash
source /data00/MRI_hackaton/scripts/venv_MRI_hackaton/bin/activate
pip install nibabel numpy pandas
```

### Single subject

```bash
python /data00/MRI_hackaton/scripts/make_cosine_basis.py \
    /data03/MRI_hackaton_data/Data_collection/fmriprep/sub-gutsaumc0010/ses-01/func/\
sub-gutsaumc0010_ses-01_task-rest_space-MNI152NLin2009cAsym_res-2_desc-preproc_bold.nii.gz
```

Example output:
```
sub-gutsaumc0010_ses-01_task-rest_..._bold.nii.gz: n_scans=300, TR=2.0s → 6 cosine regressors
Saved: .../sub-gutsaumc0010_ses-01_task-rest_..._desc-cosine180s_confounds.tsv
```

### Batch (all subjects, 10 in parallel)

```bash
source /data00/MRI_hackaton/scripts/venv_MRI_hackaton/bin/activate

fmriprep_dir="/data03/MRI_hackaton_data/Data_collection/fmriprep"

find "${fmriprep_dir}" \
    -name "*_space-MNI152NLin2009cAsym_res-2_desc-preproc_bold.nii.gz" \
    | xargs -n1 -P10 \
        python /data00/MRI_hackaton/scripts/make_cosine_basis.py
```

With a custom cutoff:
```bash
find "${fmriprep_dir}" \
    -name "*_space-MNI152NLin2009cAsym_res-2_desc-preproc_bold.nii.gz" \
    | xargs -n1 -P10 -I{} \
        python /data00/MRI_hackaton/scripts/make_cosine_basis.py {} 180
```

### Output file

The output TSV is saved alongside each BOLD file in the fmriprep derivatives:

```
fmriprep/sub-XX/ses-01/func/
├── *_desc-preproc_bold.nii.gz          ← input
├── *_desc-confounds_timeseries.tsv     ← fMRIprep confounds
└── *_desc-cosine180s_confounds.tsv     ← ✅ our custom cosine basis (output)
```

Column names: `cosine_hpf_01`, `cosine_hpf_02`, ..., `cosine_hpf_06` (exact count depends on run duration).

---

## What comes next

The cosine TSV is combined with the fMRIprep confounds TSV in the confound regression step:

```
fmriprep confounds TSV          cosine TSV
(motion 24P + aCompCor          (cosine_hpf_01 ...
 + motion_outliers)              cosine_hpf_06)
         └────────────────┬──────────────────┘
                          ▼
               combined confounds matrix
                          ▼
                    fsl_regfilt
                          ▼
                  cleaned BOLD
```

See `procedures/confound_regression.md` for the next step.

---

## References

- Lindquist, M.A., et al. (2019). Modular preprocessing pipelines can reintroduce artifacts into fMRI data. *Human Brain Mapping*, 40(8), 2358–2376. https://doi.org/10.1002/hbm.24528
- SPM DCT high-pass filter: `spm_dctmtx.m` — https://github.com/spm/spm
- fMRIprep confounds documentation: https://fmriprep.org/en/stable/outputs.html#confounds
