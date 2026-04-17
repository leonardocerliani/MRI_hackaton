# MRI Hackaton

_LC 2026-04-16_

# Abbreviations
- venv : python virtual environment
- dir : directory, folder
- sub : subject
- sw : software

# Organization of code + data
The main principle of working on storm is to have
- scripts in `/data00/[yourname]/[projectName]`
- data in `/data03` (or any other windoze disk)

`data00` 
  - is the only disk physically connected to storm, and it's the fastest, but it's also the smallest, and we should _not_ store data there. 
  - is not backed-up, therefore I strongly advise you, when you start a project, to also create a new github repo in `/data00/[yourname]/[projectName]` and link it to the remote repo on github
  - github is perfect since scripts are small - and even if you need to place some images, e.g. some MNI.nii.gz, it's ok. For big files that you might want to (temporarily) have in `data00`, there is `.gitignore`

`data[03-06]`
  - are bigger (if there is still space available), but much slower
  - they are windoze disks connected via network, therefore some linux operations (e.g. symbolic links) are not allowed. The simplest example of this is a python virtual environment, which is another reason why we need to keep the scripts on `data00`
  - they are automatically backed up
  - they need to have the typical data curation structure, with e.g. one folder for `Data_collection` and another for `Data_analysis`

Where to store the preprocessed data? For the time being, we will choose to keep them in `Data_collection`, since they do not implement any analyses. But this is flexible according to needs.


# Environment setup
- Make sure fsl is in the $PATH
  - `which fsl`
  - if it's not in the path, you need to add the following to yourr `~/.bashrc` file
  - `ls -lha` is better than `ls`, and `tree` is also very useful to see the structure of subfolders

```bash
FSLDIR=/usr/local/fsl

PATH=${FSLDIR}/share/fsl/bin:${PATH}
export FSLDIR PATH
. ${FSLDIR}/etc/fslconf/fsl.sh
```

- Make sure `pydeface` is installed (`which pydeface`) should be not null

- Make sure you are in the docker group
  - giving the command `id` from the terminal would show you which groups you are in. Make sure that there is also `docker` among them, otherwise ask me.

- Install the [niivue plugin for VS code](https://marketplace.visualstudio.com/items?itemName=KorbinianEckstein.niivue)
  - This allows inspecting the images on storm (and to add overlays!) directly from your local VS code

- Learn the very basic of python virtual environments (hereafter venv). 
  - We will (try to) use one single venv that you will store in your project folder on `data00`. For the present code, it is at `/data00/MRI_hackaton/scripts/venv_MRI_hackaton`
  - Whenever you install something new in your venv, make sure (after testing) that you export it to a `requirements.txt` file so that it will stay in the github repo, and whoever clones it will know how to reproduce your analyses with the same python packages.
    - This can be simply achieved by issuing the following once the venv is activated: `pip freeze -r requirements.txt`

- Learn the very basic of github (`git add/commit/push`)
  - and especially get used to the `.gitignore` file. For instance, we will store all the directories (hereafter dirs) with python virtual environments in there (`venv*/`) 

- Not really necessary, but make life easier
  - use `batcat` instead of `cat` (`alias cat='batcat -p'`)
  - use `btop` instead of `top` (`/usr/bin/btop`)
  - `tmux`?




# 01. Bidsification with bidscoin
[ref to GUTs tut 05_full_pipeline](https://github.com/leonardocerliani/GUTS_fmri_preproc/tree/main/TUT/05_full_pipeline)

Create a data structure suitable for bidscoin. Mine is shown below

<details><summary>PARREC data structure</summary>

```
PARREC/
├── sub-gutsaumc0010
│   └── ses-01
│       ├── sub-gutsaumc0010_ses-01_T1w_6_1.PAR
│       ├── sub-gutsaumc0010_ses-01_T1w_6_1.REC
│       ├── sub-gutsaumc0010_ses-01_task-fmrirest_bold_2_1.PAR
│       └── sub-gutsaumc0010_ses-01_task-fmrirest_bold_2_1.REC
├── sub-gutsaumc0011
│   └── ses-01
│       ├── sub-gutsaumc0011_ses-01_T1w_6_1.PAR
│       ├── sub-gutsaumc0011_ses-01_T1w_6_1.REC
│       ├── sub-gutsaumc0011_ses-01_task-fmrirest_bold_2_1.PAR
│       └── sub-gutsaumc0011_ses-01_task-fmrirest_bold_2_1.REC
...
└── sub-gutsaumc0017
    └── ses-01
        ├── sub-gutsaumc0017_ses-01_T1w_6_1.PAR
        ├── sub-gutsaumc0017_ses-01_T1w_6_1.REC
        ├── sub-gutsaumc0017_ses-01_task-fmrirest_bold_2_1.PAR
        └── sub-gutsaumc0017_ses-01_task-fmrirest_bold_2_1.REC
```

</details>

<br>

If there are some fmri acquisitions which were prematurely terminated, make sure you trim the PAR files for dcm2niix to be able to convert them to nifti

Choose which `dcm2niix` will be used by bidscoin
```bash
export dcm2niix="/usr/local/fsl/bin/dcm2niix"
```

Install `bidscoin`
```bash
# cd to the location in data00 where you want to store your venv
python3 -m venv venv_MRI_hackaton
source venv_MRI_hackaton/bin/activate
pip install bidscoin
```

Once the venv is activated, `cd` to the dir where your `PARREC` dir it and start the bidsmapper. I would suggest to use only a few subs for the bidsmapper (5-10) since otherwise it takes lots of time.

`bidsmapper PARREC/ bids/`

Once the mapping is satisfactory and saved, run the bidscoiner

`bidscoiner PARREC/ bids/`

You should end up with something like this:

<details><summary>bids data structure</summary>

```
bids/
├── README
├── code
│   └── bidscoin
│       ├── bidscoiner.errors
│       ├── bidscoiner.log
│       ├── bidscoiner.tsv
│       ├── bidsmap.yaml
│       ├── bidsmapper.errors
│       └── bidsmapper.log
├── dataset_description.json
├── participants.json
├── participants.tsv
├── sub-gutsaumc0010
│   └── ses-01
│       ├── anat
│       │   ├── sub-gutsaumc0010_ses-01_acq-ses01_T1w.json
│       │   └── sub-gutsaumc0010_ses-01_acq-ses01_T1w.nii.gz
│       ├── func
│       │   ├── sub-gutsaumc0010_ses-01_task-rest_bold.json
│       │   └── sub-gutsaumc0010_ses-01_task-rest_bold.nii.gz
│       └── sub-gutsaumc0010_ses-01_scans.tsv
...
└── sub-gutsaumc0017
    └── ses-01
        ├── anat
        │   ├── sub-gutsaumc0017_ses-01_acq-ses01_T1w.json
        │   └── sub-gutsaumc0017_ses-01_acq-ses01_T1w.nii.gz
        ├── func
        │   ├── sub-gutsaumc0017_ses-01_task-rest_bold.json
        │   └── sub-gutsaumc0017_ses-01_task-rest_bold.nii.gz
        └── sub-gutsaumc0017_ses-01_scans.tsv
```
</details>
<br>

Finally, feed the created `bids` folder into the [bidsvalidator](https://bids-standard.github.io/bids-validator/). Warnings are ok. Errors should be corrected, because fmriprep and other bisapps  process _only_ data which has passed the bidsvalidator without errors.



# 02. Anonymization with pydeface
[ref to GUTs tut 05_full_pipeline](https://github.com/leonardocerliani/GUTS_fmri_preproc/tree/main/TUT/05_full_pipeline)

```bash
# if it's the first time you run it, install it in your venv first
# pip install pydeface

n_parallel_processes=10

find bids -type f -name "*T1w*nii.gz" | xargs -n 1 -P ${n_parallel_processes} pydeface

## runnin with nohup guarantees that it will not stop if for some reason your session disconnects. 
## tmux is an even better option (to be explored)
# nohup bash -c 'find bids -type f -name "*T1w*nii.gz" | xargs -n 1 -P ${n_parallel_processes} pydeface' > deface.log 2>&1 &
```

pydeface will produce an image with the same name as the original `*T1w.nii.gz` but with the suffix `*T1w_defaced.nii.gz`. Once we have checked that everything went fine, we can overwrite the original with the defaced version, so that we keep just the anonymized T1. The original image can be regenerated from the PARREC if necessary.

```bash
for f in $(find bids -type f -name "*T1w_defaced.nii.gz"); do
    mv "$f" "${f/_defaced/}"
done
```



# 03. Skullstripping with synthstrip
[ref to 10_skull_stripping](https://github.com/leonardocerliani/GUTS_fmri_preproc/tree/main/TUT/10_skull_stripping)

[Synthstrip](https://surfer.nmr.mgh.harvard.edu/docs/synthstrip/) is an alternative to other sw for skull stripping (such as `bet` and `ANTs`). It is very recent and it uses DNN. It's superfast and it comes with freesurfer, but we will use the [docker version](https://hub.docker.com/r/freesurfer/synthstrip).

**NB**: since our data is on windoze drives, we need to change one detail in the `synthstrip-docker` provided on the website:

```bash
# Set UID and GID to avoid output files owned by root
# user = '-u %s:%s' % (os.getuid(), os.getgid())
user = ""  # instead of '-u %s:%s' % (os.getuid(), os.getgid())
```

To do them in parallel, there are several ways. Here's one very concise one using a temporary file for the T1s to be skull stripped.

```bash
bids_root="/data03/MRI_hackaton_data/Data_collection/bids"

find "${bids_root}" -type f -name "*T1w.nii.gz" > T1s_to_strip.txt

n_parallel_processes=10

xargs -a T1s_to_strip.txt -P "${n_parallel_processes}" -I {} bash -c '
    f="{}"
    out_img="${f/.nii.gz/_brain.nii.gz}"
    out_mask="${f/.nii.gz/_brain_mask.nii.gz}"

    ./synthstrip-docker-mod.sh \
        -i "$f" \
        -o "$out_img" \
        -m "$out_mask" \
        -t 10 \
        --no-csf
' # <- note the closing high quote

rm T1s_to_strip.txt
```

Now you can use the fantastic [niivue plugin for VS code](https://marketplace.visualstudio.com/items?itemName=KorbinianEckstein.niivue) to inspect the results of the skull stripping

![](./assets/niivue.png)



# 04. fMRIprep 
To generate confounds.tsv file + registration and fmri 4D in MNI using ANTs.

The procedure is described in details in the [fmriprep.md](./fmriprep.md) document.

# 05. Additional confounds generation
Generate sin/cosine predictors as temporal filtering step (those generated by fmriprep have a specific frequency)

The procedure is carried out using `scripts/make_cosine_basis.py`, which can be run in parallel for all confounds tsv files generated by fmriprep (it's very fast) using xargs. It is described in [cosine_HP_filter.md](./cosine_HP_filter.md).

# 06. Confounds regression with fsl_regfilt
nuisance regression of acompcor (5 PC) + aroma components + sin/cos basis in fsl_regfilt  

`fsl_regfilt` is a very simple command to run from the terminal, passing the original preprocessed bold file, the txt file of the confounds and an index of the columns to remove. 

However when there are 10s/100s of subjects, tasks, runs, it is impractical to run it for each selection, and actually the tough part of a purely CLI interface is the selection of the confounds to add (the number of which can be 100+).

In this case we solved the procedure by creating a simple [Shiny app](localhost:3838/http://localhost:3838/fmri_denoiser/) (on storm) that allows to make this selection using a UI, and takes as input the output derivatives of fmriprep. It scans for the `*confounds.tsv` generated by fmriprep as well as for other confounds tsv files (e.g. from aroma or custom cosine basis) provided that they have the extension `.tsv` and the string `confounds` in the filename.

Once the user has made her selection, the app generates a confound `.txt` file in the original fmriprep derivative folder (for each sub/task/run) as well as a bash script `run_regfilt.sh` to run the actual denoising. 

The configuration is also saved in a json file `denoising_config.json`, so that different configurations can be generated (and reloaded in the app) for checking the selection and to run different iterations with different selections of confounds.

![](./assets/fmri_denoiser.gif)


# 07. Smoothing 
gaussian smoothing with https://afni.nimh.nih.gov/pub/dist/doc/program_help/3dTproject.html


# Signal averaging over parcellation schemes
parcellation step to average timeseries according to ROIs


# Preprocessing with fsl Feat


# ICA Aroma



# Useful Snippets

## Add user to docker
```bash
sudo usermod -aG docker leonardo
```

## Cp sample data to data03
```bash
orig="/dataGUTS2/GUTS/WP3/Data_collection/carmen_anouk/PARREC"
dest="/data03/MRI_hackaton_data/Data_collection/PARREC"

xargs -a list_subj.txt -n 1 -P 10 -I {} rsync -av --progress "$orig/{}/" "$dest/{}/"
```