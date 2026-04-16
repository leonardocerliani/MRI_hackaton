# 04. fMRIprep

_LC 2026-04-15_

[fMRIprep documentation](https://fmriprep.org/en/stable/usage.html) | [fmriprep-docker usage](https://fmriprep.org/en/20.2.0/docker.html)

---

## What fMRIprep does (and what it does not)

fMRIprep is a robust, well-validated preprocessing pipeline for fMRI data. It is designed to be minimal and general-purpose: it handles the technically demanding parts of preprocessing, but deliberately leaves some processing choices to the analyst.

### ✅ What fMRIprep covers

| Step | Details |
|---|---|
| Skull stripping | T1w brain extraction (ANTs by default) |
| T1w → MNI registration | Nonlinear ANTs SyN; output in `MNI152NLin2009cAsym` |
| BOLD → T1w registration | BBR (boundary-based registration) |
| BOLD → MNI | Composed from the two registrations above |
| Slice timing correction | If `SliceTiming` is in the JSON sidecar (see note below) |
| Motion correction | Head motion estimated and corrected |
| Confound estimation | Motion parameters, aCompCor (WM + CSF PCA), FD, DVARS, cosine HPF basis, and more |
| ICA-based denoising | Optional; we will run ICA-AROMA separately |
| HTML QA report | Per-subject interactive report with figures |

### ❌ What fMRIprep does NOT do

These steps must be performed **after** fMRIprep, in your own pipeline:

| Step | How to do it (brief) |
|---|---|
| **Grand mean scaling** | Not performed. The preprocessed BOLD retains original scanner units. Scale to a fixed mean (e.g., 10000) if your analysis requires it: `fslmaths cleaned.nii.gz -ing 10000 scaled.nii.gz` |
| **Spatial smoothing** | Not performed. We will use AFNI `3dTproject` (see `07_smoothing.md`) |
| **Temporal filtering / nuisance regression** | Not performed. fMRIprep generates the confounds; you apply them with `fsl_regfilt` (see `06_confound_regression.md`) |
| **Parcellation** | Not performed. ROI averaging comes after cleaning (see `08_parcellation.md`) |

> **Why this design?** Keeping these steps out of fMRIprep is intentional: it lets you apply different confound strategies to the same fMRIprep output without re-running the heavy preprocessing. You can experiment with different numbers of aCompCor components, different motion thresholds, etc., all from the same derivatives folder.

---

## Pre-flight checklist

Before running fMRIprep:

- [ ] BIDS data passes the [bids-validator](https://bids-standard.github.io/bids-validator/) (no red errors; orange warnings OK)
- [ ] `.bidsignore` is in place at the BIDS root (to suppress non-BIDS files added by synthstrip — see `03_synthstrip`)
- [ ] You are in the `docker` group: run `id` and check that `docker` appears in the list
- [ ] The FreeSurfer license file exists at `$FREESURFER_HOME/license.txt`
- [ ] The derivatives and work directories exist (or will be created by fMRIprep)
- [ ] You have enough disk space: fMRIprep produces ~1–5 GB of output per subject, plus the work directory (intermediate files, can be deleted afterwards)

---

## Installing the `fmriprep-docker` wrapper
Since we are calling fmriprep with docker, we first need to install the [wrapper](https://fmriprep.org/en/20.2.0/installation.html#the-fmriprep-docker-wrapper).

Make sure the python `venv_MRI_preprocessing` is activated and then

```bash
pip install fmriprep-docker
```

## Making sure that the `WORK_DIR` is on `/data00`
This is specific to our windoze network-mounted disk condition/curse.

> **⚠️ Work directory must be on local storage**
>
> fMRIPrep uses a SQLite database in the work directory (`-w`) to track
> pipeline state. SQLite relies on POSIX file locking, which **does not work
> reliably on network-mounted filesystems** (NFS, CIFS/Samba). Running the
> work directory on `/data03` (network share) will cause
> `sqlite3.OperationalError: database is locked` errors.
>
> **Rule of thumb:**
> | Path | Storage | Use for |
> |------|---------|---------|
> | `/data00/...` | Local disk | `-w workdir` ← put it here |
> | `/data03/...` | Network mount | `bids_root`, `deriv_root` only |
>
> ```bash
> # ✅ Correct
> work_dir="./fmriprep_work_MASSIVE"
>
> # ❌ Breaks SQLite locking
> work_dir="/data03/MRI_hackaton_data/.../fmriprep_work"
> ```
>
> ⚠️ The work directory is only intermediate cache — it does not need to be
> shared. Only inputs (BIDS) and outputs (derivatives) belong on `/data03`.
>
> ⚠️ **YOU SHOULD DELETE THE WORK_DIR SOON AFTER FMRIPREP HAS FINISHED** ⚠️


## The fMRIprep command

```bash
# ── Paths ──────────────────────────────────────────────────────────────────
bids_root="/data03/MRI_hackaton_data/Data_collection/bids"
deriv_root="/data03/MRI_hackaton_data/Data_collection/fmriprep"
work_dir="./fmriprep_work_MASSIVE_DELETE_ASAP"

# ── Create the work_dir so that docker can work in it ──────────────────────
# Also removes previous versions of work_dir
[ -d ${work_dir}  ] && rm -rf ${work_dir}
[ ! -d ${work_dir} ] && mkdir -p ${work_dir}

# ── FreeSurfer license ─────────────────────────────────────────────────────
# Some users may not have FREESURFER_HOME set in their environment
FREESURFER_HOME="/usr/local/freesurfer"

# ── Parallelism ────────────────────────────────────────────────────────────
# Number of CPU cores for this fmriprep call.
# If N people run fmriprep simultaneously: nprocs ≈ total_cores / N
# Storm has 32 cores; with 4 people running at once, use nprocs=7 or 8.
nprocs=7

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
```

### Selecting specific subjects

By default, the command above processes **all subjects** found in the BIDS folder. To process only a subset, add the `--participant-label` flag:

```bash
# Process only these subjects (no "sub-" prefix needed)
fmriprep-docker ... \
    --participant-label gutsaumc0010 gutsaumc0011 gutsaumc0012
```

This is useful when multiple people run fMRIprep simultaneously — each person specifies their own subset of subjects.

---

## Flag-by-flag explanation

### `-u $(id -u):$(id -g)`
This runs docker as the current user, instead of as root (of the container). `$(id -u)` expands to your numeric user ID (e.g. `1001`) and `$(id -g)` to your primary group ID. Passing `-u UID:GID` to Docker tells the container to run fMRIprep's processes as *you* instead of root — so all files written to mounted volumes (work dir, derivatives) will be owned by your user on the host. This is done so that the user can remove the `WORK_DIR` when fmriprep has finished.

### `--no-tty`
`fmriprep-docker` automatically passes `-it` to the underlying `docker run`
command, which requests an interactive terminal (TTY). When running in the
foreground this is fine, but when detaching with `nohup ... &` there is no
terminal attached — Docker detects this and exits immediately.

### `--fs-no-reconall`
Disables FreeSurfer's cortical surface reconstruction. **Required** in our setup because our data lives on Windows-connected network drives (`/data03`), which do not support symbolic links — and FreeSurfer's reconstruction relies heavily on symlinks.

> Note: even with `--fs-no-reconall`, the FreeSurfer license is still needed because fMRIprep uses other FreeSurfer tools internally (e.g., `mri_convert`).

### `--fs-license-file`
Path to the FreeSurfer license text file. The variable `FREESURFER_HOME` is defined explicitly in the script to ensure students who don't have it in their environment can still run the command.

### `--output-spaces MNI152NLin2009cAsym:res-2`
Specifies the output space and resolution for the preprocessed BOLD:
- `MNI152NLin2009cAsym` — the standard asymmetric MNI152 template (2009, nonlinear), widely used and the default in most neuroimaging software
- `:res-2` — 2mm isotropic resolution (a good balance between spatial detail and file size/speed)

This is the same MNI space used by most atlases you'll use later (Yeo, Schaefer, etc.).

### `--fd-spike-threshold` and `--dvars-spike-threshold` — Scrubbing
These flags control the automatic detection of high-motion frames ("scrubbing"):

- **FD (Framewise Displacement)**: measures the total head displacement between consecutive volumes, derived from the 6 motion parameters. The threshold of `0.5` mm is a widely accepted standard — volumes where head motion exceeds 0.5mm are flagged.
- **DVARS**: measures the temporal derivative of the global signal RMS — in plain terms, how much the whole-brain signal "jumps" between consecutive volumes. The threshold of `1.5` is a standard value in units of percentage signal change.

For every flagged volume, fMRIprep adds a dedicated column to the confounds TSV file called `motion_outlier_XX` (a vector of zeros with a single 1 at the flagged volume). When included in your nuisance regression model, these effectively "censor" the high-motion frames — they are fit out independently and do not contribute to estimating any other regressor.

> **Note**: we generate these outlier regressors now at no extra cost. Whether to include them in the final nuisance model is a choice you make at the regression step (see `06_confound_regression.md`).

### `--ignore slicetiming`
Tells fMRIprep to skip slice timing correction. This is currently necessary because the Philips PARREC → dcm2niix conversion does not populate the `SliceTiming` field in the BOLD JSON sidecar. Without that field, fMRIprep cannot determine when each slice was acquired.

> **TODO**: Add slice timing information to the BOLD JSON sidecars and re-run fMRIprep without this flag. See the [Slice timing note](#slice-timing-note) at the bottom of this document.

### `--nprocs`
Maximum number of parallel processes for fMRIprep's internal workflow engine (nipype). fMRIprep distributes pipeline stages — and subjects — across these processes automatically. Setting this to a fraction of the machine's total cores is important when multiple people run fMRIprep simultaneously.

> `--n_cpus` and `--nthreads` are older aliases for `--nprocs` — they still work but `--nprocs` is the canonical modern flag.


### `--write-graph`
Generates a visual representation of the entire nipype workflow as a `.dot` file (Graphviz format) and renders it to a PNG. Saved in the working directory under `fmriprep_wf/graph.png`. Useful for understanding exactly what fMRIprep does under the hood — highly recommended for teaching.

### `-w ${work_dir}`
The working directory for nipype's intermediate files (intermediate registrations, resampled images, etc.). This can grow large (5–20 GB per subject) but **can be safely deleted once fMRIprep finishes successfully**. We keep it on `/data03` to avoid filling up `/data00`.

---

## Expected outputs

After a successful run, the derivatives directory will contain:

```
fmriprep/
├── sub-gutsaumc0010/
│   ├── figures/                    ← QA figures (also in the HTML report)
│   └── ses-01/
│       ├── anat/
│       │   ├── *_space-MNI152NLin2009cAsym_res-2_desc-preproc_T1w.nii.gz
│       │   ├── *_space-MNI152NLin2009cAsym_res-2_desc-brain_mask.nii.gz
│       │   └── *_from-T1w_to-MNI152NLin2009cAsym_mode-image_xfm.h5  ← warp
│       └── func/
│           ├── *_space-MNI152NLin2009cAsym_res-2_desc-preproc_bold.nii.gz  ← ✅ your data
│           ├── *_desc-confounds_timeseries.tsv                              ← ✅ confounds
│           └── *_desc-confounds_timeseries.json                             ← ✅ metadata
├── sub-gutsaumc0011/
│   └── ...
└── sub-gutsaumc0010.html           ← ✅ QA report (open in browser)
```

The two most important outputs for downstream analysis:

1. **`*_desc-preproc_bold.nii.gz`** — the preprocessed BOLD in MNI space. This is your input for confound regression.
2. **`*_desc-confounds_timeseries.tsv`** + **`.json`** — the confounds file. The JSON sidecar contains metadata for each column, including which tissue mask each aCompCor component came from (essential for selecting WM vs CSF components).

---

## Quality check: the HTML report

Open the per-subject HTML report in your browser:

```bash
# If working remotely via VS Code, you can open it directly in the browser
# Or copy to a local machine
firefox /data03/MRI_hackaton_data/Data_collection/fmriprep/sub-gutsaumc0010.html
```

Key things to check:
- **Brain mask**: does the mask correctly exclude non-brain tissue?
- **T1 → MNI registration**: does the MNI overlay align well with the standard brain?
- **BOLD → T1 registration**: are the functional and anatomical images well aligned?
- **Motion plots**: are there many high-motion frames? If so, reconsider your FD threshold.

---

## Skull stripping: fMRIprep (ANTs) vs synthstrip

fMRIprep uses **ANTs** for skull stripping by default. We already ran **synthstrip** (step 03) because it often produces cleaner brain masks. However, fMRIprep reads the original `*T1w.nii.gz` from BIDS and does its own extraction — it does not automatically use our `*T1w_brain_mask.nii.gz`.

**Current approach**: let fMRIprep do its own skull stripping. After the run, compare the two brain masks using the niivue VS Code plugin:
- fMRIprep mask: `fmriprep/.../anat/*_desc-brain_mask.nii.gz`
- synthstrip mask: `bids/.../anat/*_T1w_brain_mask.nii.gz`

**If fMRIprep's mask is poor** for one or more subjects, switch to the synthstrip brain for those subjects:

```bash
# For each problematic subject:
# 1. Back up original T1w
mv sub-XX_..._T1w.nii.gz sub-XX_..._T1w_ORIG.nii.gz

# 2. Promote the synthstrip brain as the main T1w
cp sub-XX_..._T1w_brain.nii.gz sub-XX_..._T1w.nii.gz

# 3. Add the backup to .bidsignore (add this line):
#    **/*_T1w_ORIG.nii.gz

# 4. Re-run fMRIprep with --skull-strip-t1w skip
# (tells fMRIprep not to re-strip, treating the input T1w as already brain-extracted)
```

Add `--skull-strip-t1w skip` to the fMRIprep command for those subjects only (using `--participant-label`).

---

## Slice timing note

Slice timing correction compensates for the fact that different slices in a volume are acquired at slightly different times within the TR. fMRIprep can handle this automatically if the BOLD JSON sidecar contains a `SliceTiming` field — an array of N values (one per slice) indicating when each slice was acquired, in seconds, relative to the start of the TR.

**Why it's currently disabled**: dcm2niix does not write `SliceTiming` for Philips PARREC data. Until we add this information to the sidecars, we use `--ignore slicetiming`.

**How to add it later**: create a Python script that computes the slice timing array from the known TR, number of slices, and acquisition order (sequential, interleaved, etc.) and injects it into every `*_bold.json` file in the BIDS directory. For a Philips interleaved ascending acquisition:

```python
import json, numpy as np
from pathlib import Path

tr = 2.2          # your TR in seconds
n_slices = 40     # your number of slices

# Sequential ascending (regular up) — slice 0 first, going up
slice_times = [i * (tr / n_slices) for i in range(n_slices)]

# # Sequential descending (regular down) — top slice first, going down
# slice_times = [(n_slices - 1 - i) * (tr / n_slices) for i in range(n_slices)]

# # Interleaved ascending (Philips default for some protocols) — odds then evens
# interleaved_order = list(range(0, n_slices, 2)) + list(range(1, n_slices, 2))
# slice_times = [interleaved_order.index(i) * (tr / n_slices) for i in range(n_slices)]

bids_root = Path("/data03/MRI_hackaton_data/Data_collection/bids")

for json_file in bids_root.rglob("*_bold.json"):
    with open(json_file) as f:
        sidecar = json.load(f)
    sidecar["SliceTiming"] = slice_times
    with open(json_file, "w") as f:
        json.dump(sidecar, f, indent=2)
    print(f"Updated: {json_file}")
```

Once the sidecars are updated, remove `--ignore slicetiming` from the fMRIprep command and re-run. Also consider the `--slice-time-ref` option (default `0.5`, corresponding to the middle of the TR) which controls to which timepoint in the TR the data will be aligned — the default is fine in most cases.

---

## What comes next

After fMRIprep, the heavy lifting is done. The remaining steps operate entirely on the confounds TSV and the MNI-space BOLD:

1. **ICA-AROMA** (`05_ICA_aroma.md`) — motion artifact detection using independent component analysis
2. **Confound regression** (`06_confound_regression.md`) — regress out:
   - 24 motion parameters (6 + derivatives + quadratics)
   - 5 aCompCor components from WM + 5 from CSF (selected from confounds TSV using JSON metadata)
   - `motion_outlier_*` columns (scrubbing regressors, if desired)
   - Custom 180s cosine high-pass filter basis (generated in Python — **not** the `cosine_*` columns in fMRIprep's confounds TSV, which correspond to a 128s cutoff)
3. **Smoothing** (`07_smoothing.md`) — Gaussian smoothing with AFNI `3dTproject`
4. **Parcellation** (`08_parcellation.md`) — ROI-average timeseries using Yeo, Schaefer, or other atlases
