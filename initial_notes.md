# MRI Hackaton - Preprocessing

LC 2026-03-27

## 20 - 24 April 2026

`/data00/MRI_hackaton`

Here we will edit and store both documentation and scripts for the MRI hackaton. I made this directory completely open so that everybody can edit everything. 

The directory is linked to a [github repo](https://github.com/leonardocerliani/MRI_hackaton) and I will push modifications to the repo frequently.


## Programme and environment setup

The main steps for the preprocessing for Anouk and I are:
- skullstripping - we'll check the output of fmriprep and if there are problems we will use synthstrip and fmriprep forcing no skull stripping

- fMRIprep run (generating confounds file with sin and cosine)
nuisance regression with WM+CSF+FD(+6 parameters?) 

- ICA aroma to detect motion components to regress out with the rest

- regress with sin/cosine predictors as temporal filtering step

- gaussian smoothing with [AFNI 3dTproject](https://afni.nimh.nih.gov/pub/dist/doc/program_help/3dTproject.html)

- using MNI parcellation schemes (e.g. Yeo7, Yeo17) to calculate ROI-based average time courses

_Iff we have time_, we will also prepare a tool to inspect the results of the preprocessing including a simple ISC like the ones we did with Francisca [here](http://localhost:3838/QA_GUTS/) (open the port 3838 on storm to see it locally on your computer). Ideally this should be able to get the location of your folder with fmriprep+preprocessing and do everything by itself

One big part of the whole feat will **preparing the environment**. Tentatively, we need to have all of the following available

- data in bids (prepared using bidscoin)
- fmriprep docker image
- synthstrip docker
- fsl (for various things including `fsl_regfilt`)
- ICA aroma
- python (of course)
- AFNI for gaussian smoothing (probably the only thing still missing)
- some parcellation schemes (Yeo, Schaefer, Juelich, add your favourite - I already have most of these atlases)

NB: you can inspect docker images with `docker image ls`. I notice that for some tools we have multiple versions, so we will also decide which one to use/keep and which ones to remove.

## Sample data
The procedures described here - and relative scripts - will be written to work on sample data, so that you can have a reference to a known working dataset.

Tentatively, I will be using a subset of Anouk's data in `/dataGUTS2/GUTS/sample_data`, but let me know (quickly) if you prefer something else.

You will need to modify the scripts so that they work on your own data, and we will make it so that this can be done in the simple and most evident way. 

I would suggest when you apply the scripts to your data to **start with a subsample of your participants in a folder that you can easily delete and recreate**, because of course there will be some choices to do and some mistakes along the way. 

## Important note about the windoze disks
As you know, the disks where our data lies are not physically connected to storm, rather they are connected via network to a windoze system. Therefore any operation related to symbolic links - which are a common feature in *nix - is not available. We will need to adapt the scripts accordingly (e.g. in synthstrip).

For our purposes, one of the main limitation is that we cannot carry out surface reconstruction, because as Anouk noticed this creates symlinks. In order to do so, we would need to temporarily move the bids to `/data00`, run fmriprep and then bring them back to `/dataGUTS2`. We would also need to do this in batches, as you know that `/data00` has a limited space.

**Therefore, for the moment we will run fmriprep with the `--no-freesurfer` option, since we do not have pressing needs to carry out surface-based analysis**. Later on you can adapt the fmriprep part of the procedure to include the move back and forth from `/data00` in batches. (Also note that running freesurfer requires also a valid license file).


## Useful links
- running fmriprep in a docker: [nipreps](https://www.nipreps.org/apps/docker/), [fmriprep](https://fmriprep.org/en/20.2.0/docker.html)
- [various tutorials](https://github.com/leonardocerliani/GUTS_fmri_preproc/tree/main/TUT), some about the things we will do


## Other notes
How to create a directory which is fully editable by all users

```bash
chmod 1777 /data00/MRI_hackaton 
setfacl -d -m u::rwx,g::rwx,o::rwx /data00/MRI_hackaton
```
