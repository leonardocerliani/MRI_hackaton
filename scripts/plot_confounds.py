import marimo

__generated_with = "0.1.0"
app = marimo.App(width="full")


@app.cell
def import_and_setup():
    import marimo as mo
    import pandas as pd
    import os
    import matplotlib.pyplot as plt
    import numpy as np

    # ROOT PATHS: Adjust these if folders are moved.
    derivative_root = "/data03/MRI_hackaton_data/Data_collection/fmriprep"
    subject_list_path = "/data03/MRI_hackaton_data/Data_collection/list_subj.txt"
    
    available_subjects = []
    
    # Try 1: Load from your text file
    if os.path.exists(subject_list_path):
        with open(subject_list_path, "r") as _f_subj:
            available_subjects = sorted([line.strip() for line in _f_subj if line.strip()])
    
    # Try 2 (FALLBACK): Scan folder if no list exists
    if not available_subjects and os.path.exists(derivative_root):
         available_subjects = sorted([d for d in os.listdir(derivative_root) if d.startswith("sub-")])
    
    if not available_subjects:
        available_subjects = ["sub-unknown"]

    # STEP 1: Subject Selection Box
    subject_select = mo.ui.dropdown(
        options=available_subjects, 
        label="1. Pick Subject",
        value=available_subjects[0] if available_subjects else None
    )
    
    return (mo, pd, os, plt, np, derivative_root, subject_list_path, available_subjects, subject_select)


@app.cell
def select_session(mo, os, derivative_root, subject_select):
    if not subject_select.value:
        mo.stop(True, mo.md("Please select a subject first."))
        
    subj_folder = os.path.join(derivative_root, subject_select.value)
    if not os.path.exists(subj_folder):
        subj_folder = os.path.join(derivative_root, "fmriprep", subject_select.value)

    sessions = []
    if os.path.exists(subj_folder):
        sessions = sorted([d for d in os.listdir(subj_folder) if d.startswith("ses-")])
    
    if not sessions:
        sessions = ["no-session"]

    # STEP 2: Session Selection Box
    session_select = mo.ui.dropdown(
        options=sessions,
        label="2. Pick Session",
        value=sessions[0]
    )
    
    return (subj_folder, sessions, session_select)


@app.cell
def select_run(mo, os, subj_folder, session_select):
    if not session_select.value:
        mo.stop(True, mo.md("Please select a session first."))

    if session_select.value == "no-session":
        func_dir = os.path.join(subj_folder, "func")
    else:
        func_dir = os.path.join(subj_folder, session_select.value, "func")
    
    run_paths = {}
    if os.path.exists(func_dir):
        _files = sorted([_f for _f in os.listdir(func_dir) if _f.endswith("confounds_timeseries.tsv")])
        for _f in _files:
            _parts = _f.split("_")
            run_label = next((p for p in _parts if p.startswith("run-")), "run-01")
            run_paths[run_label] = os.path.join(func_dir, _f)
    
    runs = sorted(list(run_paths.keys()))

    # STEP 3: Run Selection Box
    run_select = mo.ui.dropdown(
        options=runs,
        label="3. Pick Run",
        value=runs[0] if runs else None
    )
    
    return (func_dir, runs, run_paths, run_select)


@app.cell
def generate_plots(mo, pd, plt, run_select, run_paths, np, session_select, subject_select):
    if not (run_select and run_select.value):
        mo.stop(True, mo.md("No BOLD data found for this selection."))

    # Load the motion data
    file_path = run_paths[run_select.value]
    df = pd.read_csv(file_path, sep="\t")

    # Setup 3 charts stacked vertically
    fig, axs = plt.subplots(3, 1, figsize=(10, 10), sharex=True)

    # Translation
    axs[0].plot(df[['trans_x', 'trans_y', 'trans_z']])
    axs[0].set_title('Translation (mm)')
    axs[0].legend(['X', 'Y', 'Z'], loc='upper right')
    axs[0].grid(True, alpha=0.3)

    # Rotation
    rot_cols = ['rot_x', 'rot_y', 'rot_z']
    rot_deg = df[rot_cols] * (180 / np.pi)
    axs[1].plot(rot_deg)
    axs[1].set_title('Rotation (Degrees)')
    axs[1].legend(['Pitch', 'Roll', 'Yaw'], loc='upper right')
    axs[1].grid(True, alpha=0.3)

    # FD
    fd = df['framewise_displacement'].fillna(0)
    axs[2].plot(fd, color='black', alpha=0.7)
    axs[2].axhline(y=0.5, color='red', linestyle='--', label='0.5mm Cutoff')
    axs[2].set_title('Framewise Displacement (FD)')
    axs[2].set_ylabel('mm')
    axs[2].legend(loc='upper right')
    axs[2].grid(True, alpha=0.3)
    
    mean_fd = fd.mean()
    max_fd = fd.max()
    
    # Using a single variable for assembly
    ui_assembly = mo.vstack([
        mo.md(f"## Motion QC Tool: {subject_select.value}"),
        mo.hstack([subject_select, session_select, run_select], justify="start"),
        mo.md(f"Viewing: **{session_select.value} | {run_select.value}**"),
        mo.md(f"- **Mean FD:** {mean_fd:.3f} mm\n- **Max FD:** {max_fd:.3f} mm"),
        mo.as_html(fig)
    ])
    
    # We display it by just referencing it at the end of the cell
    ui_assembly
    return (ui_assembly, mean_fd, max_fd, df, fig, axs)


if __name__ == "__main__":
    app.run()