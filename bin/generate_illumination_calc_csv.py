#!/usr/bin/env python3
"""
Generate load_data.csv for CellProfiler illumination calculation.

This script generates load_data.csv files for the illumination calculation step,
which uses original multi-channel images.

Uses only Python standard library - no external dependencies.
"""

import argparse
import csv
import glob
import os
import re
import sys
from typing import Dict, List, Optional


def parse_original_image(filename: str) -> Optional[Dict]:
    """
    Parse original multi-channel image filename.

    Pattern: WellA1_PointA1_0000_ChannelCHN1,CHN2,CHN3_Seq0000.ome.tiff

    Returns dict with: plate (if available), well, site, channels (list), frames (dict)
    """
    # Extract well, site, and channel info
    pattern = r'Well([A-Z]\d+)_Point[A-Z]\d+_(\d+)_Channel([^_]+)_Seq\d+\.ome\.tiff?'
    match = re.search(pattern, filename)

    if not match:
        return None

    well = match.group(1)
    site = int(match.group(2))
    channels_str = match.group(3)

    # Parse channels - could be comma-separated
    channels = [ch.strip() for ch in channels_str.split(',')]

    # Build frame mapping - each channel gets its sequential frame number
    frames = {ch: idx for idx, ch in enumerate(channels)}

    return {
        'well': well,
        'site': site,
        'channels': channels,
        'frames': frames
    }


def infer_plate_from_path(file_path: str) -> str:
    """
    Try to infer plate name from file path.
    Looks for 'Plate{number}' pattern in the path.
    """
    match = re.search(r'Plate(\d+)', file_path)
    if match:
        return f'Plate{match.group(1)}'
    return 'Unknown'


def collect_and_group_files(images_dir: str) -> Dict:
    """
    Collect and group image files by (plate, well, site).

    Returns:
        Dict mapping (plate, well, site) -> {'images': {...}}
    """
    # Validate input directory exists
    if not os.path.isdir(images_dir):
        raise FileNotFoundError(f"Images directory not found: {images_dir}")

    # Find image files
    pattern = os.path.join(images_dir, "**", "*")
    try:
        all_files = glob.glob(pattern, recursive=True)
    except Exception as e:
        raise IOError(f"Error searching for files in {images_dir}: {e}")

    # Filter to actual files matching pattern
    file_pattern = r'.*\.ome\.tiff?$'
    image_files = [
        f for f in all_files
        if os.path.isfile(f) and re.search(file_pattern, os.path.basename(f))
    ]

    if not image_files:
        raise ValueError(
            f"No image files found matching pattern '{file_pattern}' in {images_dir}\n"
            f"Expected pattern: WellA1_PointA1_0000_ChannelCHN1,CHN2_Seq0000.ome.tiff"
        )

    print(f"✓ Found {len(image_files)} image files to process", file=sys.stderr)

    # Group files
    grouped = {}
    parse_errors = []
    missing_metadata = []

    for img_path in image_files:
        filename = os.path.basename(img_path)

        try:
            parsed = parse_original_image(filename)
        except Exception as e:
            parse_errors.append((filename, str(e)))
            print(f"⚠ Error parsing filename '{filename}': {e}", file=sys.stderr)
            continue

        if not parsed:
            parse_errors.append((filename, "Failed to match expected pattern"))
            print(f"⚠ Skipping '{filename}': does not match expected pattern", file=sys.stderr)
            continue

        # Validate required metadata fields
        try:
            plate = parsed.get('plate', infer_plate_from_path(img_path))
            well = parsed['well']
            site = parsed['site']
        except KeyError as e:
            missing_metadata.append((filename, str(e)))
            print(f"⚠ Missing required metadata in '{filename}': {e}", file=sys.stderr)
            continue

        key = (plate, well, site)

        if key not in grouped:
            grouped[key] = {'images': {}}

        # Store multi-channel image with frames info
        grouped[key]['images']['_file'] = filename
        grouped[key]['images']['_parsed'] = parsed

    # Report parsing summary
    if parse_errors:
        print(f"\n⚠ Warning: Failed to parse {len(parse_errors)} file(s)", file=sys.stderr)
    if missing_metadata:
        print(f"⚠ Warning: {len(missing_metadata)} file(s) had missing metadata", file=sys.stderr)

    print(f"✓ Successfully grouped {len(grouped)} unique (plate, well, site) combinations", file=sys.stderr)

    return grouped


def generate_csv_rows(grouped: Dict, range_skip: int = 1) -> List[Dict]:
    """
    Generate CSV rows from grouped file data.
    """
    if not grouped:
        raise ValueError("No grouped files to generate CSV rows from")

    # Apply subsampling if needed
    all_sites = sorted(set(site for _, _, site in grouped.keys()))
    selected_sites = [site for i, site in enumerate(all_sites) if i % range_skip == 0]

    if not selected_sites:
        raise ValueError(f"No sites selected with range_skip={range_skip}")

    print(f"✓ Selected {len(selected_sites)} site(s) from {len(all_sites)} total sites", file=sys.stderr)

    rows = []
    row_errors = []

    for (plate, well, site), file_data in sorted(grouped.items()):
        if site not in selected_sites:
            continue

        try:
            parsed = file_data['images']['_parsed']
            filename = file_data['images']['_file']

            if 'channels' not in parsed or 'frames' not in parsed:
                raise ValueError(f"Missing channels or frames data for {filename}")

            # Build metadata columns
            row = {
                'Metadata_Plate': plate,
                'Metadata_Well': well,
                'Metadata_Site': site
            }

            # Add FileName and Frame for each channel
            for channel in parsed['channels']:
                if channel not in parsed['frames']:
                    raise KeyError(f"Frame information missing for channel '{channel}'")

                frame = parsed['frames'][channel]
                row[f'FileName_Orig{channel}'] = filename
                row[f'Frame_Orig{channel}'] = frame

            rows.append(row)

        except (KeyError, ValueError) as e:
            row_errors.append((f"{plate}/{well}/Site{site}", str(e)))
            print(f"⚠ Error generating row for {plate}/{well}/Site{site}: {e}", file=sys.stderr)
            continue

    if row_errors:
        print(f"\n⚠ Warning: Failed to generate {len(row_errors)} row(s)", file=sys.stderr)

    if not rows:
        raise ValueError(
            f"Failed to generate any valid CSV rows. "
            f"Processed {len(grouped)} file groups, encountered {len(row_errors)} errors"
        )

    print(f"✓ Generated {len(rows)} CSV row(s)", file=sys.stderr)

    return rows


def write_csv(rows: List[Dict], output_file: str):
    """Write rows to CSV with proper column ordering."""
    if not rows:
        raise ValueError("No rows to write - cannot create empty CSV")

    # Get all column names
    all_cols = set()
    for row in rows:
        all_cols.update(row.keys())

    # Order: metadata columns first, then sorted FileName/Frame columns
    metadata_cols = ['Metadata_Plate', 'Metadata_Well', 'Metadata_Site']
    file_cols = sorted([c for c in all_cols if c not in metadata_cols])
    fieldnames = metadata_cols + file_cols

    print(f"✓ Writing CSV with {len(fieldnames)} columns: {', '.join(fieldnames)}", file=sys.stderr)

    try:
        with open(output_file, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)
    except IOError as e:
        raise IOError(f"Failed to write CSV to {output_file}: {e}")
    except Exception as e:
        raise RuntimeError(f"Unexpected error writing CSV: {e}")

    print(f"✓ Successfully generated {output_file} with {len(rows)} rows")


def main():
    parser = argparse.ArgumentParser(
        description='Generate load_data.csv for CellProfiler illumination calculation'
    )
    parser.add_argument(
        '--images-dir',
        default='./images',
        help='Directory containing input images (default: ./images)'
    )
    parser.add_argument(
        '--output',
        default='load_data.csv',
        help='Output CSV file path (default: load_data.csv)'
    )
    parser.add_argument(
        '--range-skip',
        type=int,
        default=1,
        help='Subsampling interval - use every Nth site (default: 1 = all sites)'
    )

    args = parser.parse_args()

    if args.range_skip < 1:
        parser.error(f"--range-skip must be >= 1, got {args.range_skip}")

    print(f"\n{'='*60}", file=sys.stderr)
    print(f"CellProfiler Illumination Calculation CSV Generator", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"Images directory: {args.images_dir}", file=sys.stderr)
    if args.range_skip > 1:
        print(f"Subsampling: every {args.range_skip} sites", file=sys.stderr)
    print(f"Output file: {args.output}", file=sys.stderr)
    print(f"{'='*60}\n", file=sys.stderr)

    try:
        # Collect and group files
        print(f"Step 1/3: Collecting and grouping files...", file=sys.stderr)
        grouped = collect_and_group_files(args.images_dir)

        # Generate rows
        print(f"\nStep 2/3: Generating CSV rows...", file=sys.stderr)
        rows = generate_csv_rows(grouped, args.range_skip)

        # Write CSV
        print(f"\nStep 3/3: Writing CSV file...", file=sys.stderr)
        write_csv(rows, args.output)

        print(f"\n{'='*60}", file=sys.stderr)
        print(f"✓ SUCCESS: CSV generation completed", file=sys.stderr)
        print(f"{'='*60}\n", file=sys.stderr)

        return 0

    except FileNotFoundError as e:
        print(f"\n❌ ERROR: File or directory not found", file=sys.stderr)
        print(f"   {e}", file=sys.stderr)
        return 1
    except ValueError as e:
        print(f"\n❌ ERROR: Invalid data or configuration", file=sys.stderr)
        print(f"   {e}", file=sys.stderr)
        return 1
    except IOError as e:
        print(f"\n❌ ERROR: File I/O error", file=sys.stderr)
        print(f"   {e}", file=sys.stderr)
        return 1
    except KeyError as e:
        print(f"\n❌ ERROR: Missing required metadata field", file=sys.stderr)
        print(f"   {e}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"\n❌ ERROR: Unexpected error occurred", file=sys.stderr)
        print(f"   {type(e).__name__}: {e}", file=sys.stderr)
        import traceback
        print(f"\nTraceback:", file=sys.stderr)
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
