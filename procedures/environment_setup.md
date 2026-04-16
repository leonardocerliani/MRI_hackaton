# Environment setup

## First and foremost: ssh + vs code
We will mostly operate from the terminal (except for bidscoin and Fast) and edit scripts/documentation located on storm in VS code, therefore:

- Make sure you have access to storm using an ssh key
- Make sure you have VS code installed, and configured for easy connection to storm

How to achieve this is explained in the [SBL terminal tutorial](https://github.com/leonardocerliani/SBL_terminal_tutorial/blob/main/03_storm_access/02_ssh_vs_code/02_ssh_vs_code.md) from a few months ago (should be smooth also for windoze users).

Also, make sure you install the [niivue extension for VS code](https://marketplace.visualstudio.com/items?itemName=KorbinianEckstein.niivue) that allows you to view nifti images and overlays directly in VS code.

## Scripts and data organization on storm
Storm has one relatively small physically connected disk (`data00`) and several large network-connected disks (hereafter: windoze disks). This is a peculiar setting that will require us several workaround to standard procedures you can find online.

In general, you will have the _only the scripts_ in your named folder in `data00` (e.g. `/data00/leonardo/`) and run them from there on data which will be in one of the windoze disks (e.g. `/data03/[project name]`). 

Importantly, data on windoze disks _should_ adhere to the data curation policies, which could be a bit complex if you do not already did this. If you want to create a folder like `/data03/MRI_hackaton_leonardo` you can, but you should make sure that you delete is soon after we finish our hackaton, and you already ported what you learned on your actual data-curation-compliant data folder on storm.

## Github
This is optional, but I still recommend it: fork this repo in your own github account, clone it in your named directory in `data00` (e.g. `/data00/leonardo/`, resulting in `/data00/leonardo/MRI_Hackaton`) so that you can freely modify all the scripts and documents to your needs, and push them to the github account. 

I strongly advice this not only because you can personalize what we will do, but also because in this way you will get used to have your scripts on github. This is particularly important since _data00 is not backed up_, and since it's the best location where you can keep your scripts (fast and requires no data curation), even if storm dies tomorrow, you will still have your scripts and you can just re-apply them on storm2 on your backed up data in the windoze disks.

## Docker and python virtual environments
We will run some logic that is hosted on docker containers, and other that require their own python virtual environment.

For docker, make sure you belong to the docker group (go to storm and check by issueing `id` in the terminal), otherwise I will take care of this on the spot.

For python virtual environments (hereafter venv), make sure you know the very basic of it:
- how to create a venv
- how to activate / deactivate it
- how to install python libraries in it
- how to save its content to a `requirements.txt`

Specifically, we will (try to) keep everything into a single vevn which we will call `venv_MRI_preproc`. You will store this in your own folder on `data00`.


## bidscoin
[bidscoin](https://bidscoin.readthedocs.io/en/latest/index.html) will convert the PARREC to nifti and place them in a bids-compliant structure. A [previous tutorial](https://github.com/leonardocerliani/GUTS_fmri_preproc/tree/main/TUT/04_bidscoin) explains the procedure.

biscoin should be installed in the venv.

## fmriprep docker image
We will use `nipreps/fmriprep  25.2.3`, as it is the same used in halfpipe (info from a few months ago) 

fmriprep is already present on storm, as you can see from `docker image ls | grep fmriprep`. Since we will use the `fmriprep-docker` wrapper, we will need to install this in the venv.

## synthstrip docker
We will use [synthstrip](https://surfer.nmr.mgh.harvard.edu/docs/synthstrip/) since it appears to provide overall superior results with respect to ANTs (used inside fmriprep). However we will also let fmriprep run skull stripping with ANTs and then compare the results.

`synthstrip-docker` is a bash wrapper about a docker container. The container is already present on storm (`docker image ls | grep synthstrip`).

Due to our windoze situation, we need to make a small modification to the distributed wrapper, which you can find in the `scripts/synthstrip-docker-mod.sh` file.

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

---


# Useful stuff

## tmux — keeping jobs alive after disconnection

`tmux` creates persistent terminal sessions on Storm that survive network disconnections. You start a session, detach from it (it keeps running in the background), and reattach to it later from any terminal — even from a completely new SSH connection.

### The 4 commands you need

```bash
# Start a new named session
tmux new-session -s my_session

# Detach from the current session (leave it running)
# Inside tmux: press  Ctrl+B  then  D

# List all active sessions
tmux ls

# Reattach to a session
tmux attach -t my_session
```

### Typical use: running fMRIprep

```bash
# 1. Start a named session
tmux new-session -s fmriprep

# 2. Inside the session, launch the script and log everything
bash /data00/MRI_hackaton/scripts/run_fmriprep.sh 2>&1 | tee fmriprep_$(date +%Y%m%d_%H%M).log

# 3. Detach: Ctrl+B, then D
#    → fMRIprep keeps running; you can close your laptop

# 4. Come back later and reattach to check progress
tmux attach -t fmriprep

# 5. When fMRIprep is done, you can kill the session
tmux kill-session -t fmriprep
```

> **Note on `tee`**: `2>&1 | tee logfile.log` does two things at once — it shows the output in your terminal *and* writes it to a log file. Without `tee`, you'd have to choose one or the other.

> **Tip**: If you accidentally close the terminal without detaching (e.g. the SSH connection drops), tmux keeps the session alive anyway. Just `tmux attach -t fmriprep` from your next login.
