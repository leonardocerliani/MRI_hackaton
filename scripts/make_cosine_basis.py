#!/usr/bin/env python3
"""
Generate a DCT high-pass filter basis for fMRI nuisance regression.
See procedures/cosine_HP_filter.md for the rationale.

Usage
-----
# Single subject (default cutoff: 180s):
python make_cosine_basis.py path/to/bold.nii.gz

# Single subject with custom cutoff:
python make_cosine_basis.py path/to/bold.nii.gz 180

# Batch — all subjects in fmriprep derivatives, 10 in parallel:
fmriprep_dir="/data03/MRI_hackaton_data/Data_collection/fmriprep"

find "${fmriprep_dir}" -name "*_space-MNI152NLin2009cAsym_res-2_desc-preproc_bold.nii.gz" \\
    | xargs -n1 -P10 python make_cosine_basis.py

# Batch with custom cutoff:
find "${fmriprep_dir}" -name "*_space-MNI152NLin2009cAsym_res-2_desc-preproc_bold.nii.gz" \\
    | xargs -n1 -P10 -I{} python make_cosine_basis.py {} 180

Output
------
A TSV file saved alongside the BOLD file:
    *_desc-cosine180s_confounds.tsv

with columns: cosine_hpf_01, cosine_hpf_02, ...

This TSV is then combined with the fMRIprep confounds TSV in the
confound regression step (see procedures/confound_regression.md).
"""

import sys
import numpy as np
import pandas as pd
import nibabel as nib
from pathlib import Path


def dct_highpass_basis(n_scans, tr, cutoff_sec=180.0):
    """SPM-style DCT high-pass basis matrix (n_scans × n_basis)."""
    n = np.arange(n_scans)
    n_basis = int(np.floor(2 * n_scans * tr / cutoff_sec))
    if n_basis < 1:
        return np.empty((n_scans, 0))
    X0 = np.zeros((n_scans, n_basis))
    for k in range(1, n_basis + 1):
        X0[:, k - 1] = np.cos((np.pi / n_scans) * (n + 0.5) * k)
    return X0


# ── Read NIfTI ─────────────────────────────────────────────────────────────
bold_path = Path(sys.argv[1])
cutoff    = float(sys.argv[2]) if len(sys.argv) > 2 else 180.0

img     = nib.load(bold_path)
n_scans = img.shape[3]
tr      = float(img.header.get_zooms()[3])   # TR in seconds (pixdim[4])

# ── Compute and save ────────────────────────────────────────────────────────
X0 = dct_highpass_basis(n_scans, tr, cutoff_sec=cutoff)
print(f"{bold_path.name}: n_scans={n_scans}, TR={tr}s → {X0.shape[1]} cosine regressors")

cols     = [f"cosine_hpf_{k+1:02d}" for k in range(X0.shape[1])]
out_path = bold_path.parent / bold_path.name.replace(
               "_desc-preproc_bold.nii.gz",
               f"_desc-cosine{int(cutoff)}s_confounds.tsv")

pd.DataFrame(X0, columns=cols).to_csv(out_path, sep="\t", index=False, float_format="%.8f")
print(f"Saved: {out_path}")
