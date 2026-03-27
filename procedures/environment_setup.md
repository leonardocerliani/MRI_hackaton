# Environment setup

## bidscoin


## fmriprep docker image
We will use `nipreps/fmriprep  25.2.3`, as it is the same used in halfpipe (info from a few months ago) 

## synthstrip docker
`freesurfer/synthstrip  latest`

## fsl
To have fsl in your path, make sure the following lines are in your `~/.bashrc`

```bash
FSLDIR=/usr/local/fsl

PATH=${FSLDIR}/share/fsl/bin:${PATH}
export FSLDIR PATH
. ${FSLDIR}/etc/fslconf/fsl.sh
```

Then open a new terminal and type e.g. `fslmaths` to check that everything is working.

## python 
We will use Python 3.10.9 since it is the one shipped with fsl, and after setting fsl in your path, the command `which python` should return an fsl path.

## ICA aroma installed in its own `venv`
TODO - Note that ICA aroma requires that the functional and T1w have been registered using [fnirt](https://fsl.fmrib.ox.ac.uk/fsl/docs/registration/fnirt/index.html), therefore in any case we will need to do some registrations in fsl.

## AFNI for gaussian smoothing (probably the only thing still missing)
TODO

## some parcellation schemes (Yeo, Schaefer, Juelich, add your favourite - I already have most of these atlases)
TODO - We will need to make sure that they are in the MNI space that fmriprep uses