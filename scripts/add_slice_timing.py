#!/usr/bin/env python3
import json
import os
import glob
import argparse

"""
Script to add SliceTiming metadata to BIDS JSON sidecars.
Specifically designed for Philips PAR/REC sourced data where timing is often missing.

Usage:
python3 add_slice_timing.py /path/to/bids_root --tr 2.2 --nslices 40 --order ascending
python3 add_slice_timing.py /path/to/bids_root --tr 2.2 --nslices 40 --force  # Overwrite if already present
"""

def calculate_slice_timing(tr, n_slices, order='ascending'):
    """ Calculates slice timing array for BIDS (in seconds) """
    slice_duration = tr / n_slices
    timings = [0.0] * n_slices # Initialize with zeros
    
    if order == 'interleaved':
        # Default interleaved: Even then Odd (0, 2, 4... then 1, 3, 5...)
        idx = 0
        # Evens
        for s in range(0, n_slices, 2):
            timings[s] = idx * slice_duration
            idx += 1
        # Odds
        for s in range(1, n_slices, 2):
            timings[s] = idx * slice_duration
            idx += 1
    elif order == 'ascending':
        # 0, 1, 2, 3...
        for s in range(n_slices):
            timings[s] = s * slice_duration
    elif order == 'descending':
        # N-1, N-2, ... 0
        for s in range(n_slices):
            timings[s] = (n_slices - 1 - s) * slice_duration
    
    return [round(t, 6) for t in timings]

def main():
    parser = argparse.ArgumentParser(
        description='Add SliceTiming to BIDS JSON files.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 add_slice_timing.py /path/to/bids --tr 2.2 --nslices 40 --order ascending
  python3 add_slice_timing.py /path/to/bids --tr 2.2 --nslices 40 --order interleaved --force
        """
    )
    parser.add_argument('bids_dir', help='Path to BIDS root directory')
    parser.add_argument('--tr',      type=float, required=True,
                        help='Repetition Time in seconds (e.g. 2.2)')
    parser.add_argument('--nslices', type=int,   required=True,
                        help='Number of slices (e.g. 40)')
    parser.add_argument('--order', choices=['interleaved', 'ascending', 'descending'],
                        default='ascending', help='Slice acquisition order (default: ascending)')
    parser.add_argument('--force', action='store_true',
                        help='Overwrite SliceTiming if already present')

    args = parser.parse_args()

    # Validate numeric inputs
    if args.tr <= 0:
        parser.error(f"--tr must be a positive number, got {args.tr}")
    if args.nslices <= 0:
        parser.error(f"--nslices must be a positive integer, got {args.nslices}")

    # Print parameter summary before doing anything
    print()
    print("=" * 50)
    print("  add_slice_timing — parameters")
    print("=" * 50)
    print(f"  BIDS directory : {args.bids_dir}")
    print(f"  TR             : {args.tr} s")
    print(f"  N slices       : {args.nslices}")
    print(f"  Order          : {args.order}")
    print(f"  Force          : {args.force}")
    print("=" * 50)
    print()

    # Search for all bold.json files
    # Checks sub-*/ses-*/func/ and sub-*/func/
    json_files = glob.glob(os.path.join(args.bids_dir, 'sub-*', 'ses-*', 'func', '*_bold.json'))
    if not json_files:
        json_files = glob.glob(os.path.join(args.bids_dir, 'sub-*', 'func', '*_bold.json'))

    if not json_files:
        print(f"Error: No *_bold.json files found in {args.bids_dir}")
        return

    slice_timing = calculate_slice_timing(args.tr, args.nslices, args.order)
    print(f"Calculated SliceTiming ({args.order}): {slice_timing[:3]} ... {slice_timing[-3:]}")

    for jf in json_files:
        try:
            with open(jf, 'r') as f:
                data = json.load(f)
            
            # Safety check: See if SliceTiming already exists
            if 'SliceTiming' in data:
                if not args.force:
                    print(f"⚠️  Skipped (SliceTiming already present): {os.path.basename(jf)}")
                    continue
                else:
                    print(f"🔄 Overwriting existing SliceTiming: {os.path.basename(jf)}")
            
            # Update metadata
            data['SliceTiming'] = slice_timing
            
            # Ensure RepetitionTime is explicitly set
            if 'RepetitionTime' not in data:
                data['RepetitionTime'] = args.tr
            
            # Philips data often needs SliceEncodingDirection defined (usually 'k')
            if 'SliceEncodingDirection' not in data:
                data['SliceEncodingDirection'] = 'k'
            
            with open(jf, 'w') as f:
                json.dump(data, f, indent=4)
            
            print(f"✅ Updated: {os.path.basename(jf)}")
        except Exception as e:
            print(f"❌ Failed to update {jf}: {e}")

if __name__ == "__main__":
    main()