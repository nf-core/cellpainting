#!/usr/bin/env python3
"""
Generate load_data.csv for CellProfiler illumination calculation.

This script generates load_data.csv files for the illumination calculation step
by reading metadata from a JSON file passed from Nextflow.

Uses only Python standard library - no external dependencies.
"""

import argparse
import csv
import json
import sys
from typing import Dict, List


def read_metadata_json(json_path: str) -> Dict:
    """
    Read and validate metadata JSON file.

    Expected structure:
    {
        "meta": {
            "id": "...",
            "batch": "...",
            "plate": "...",
            "channel": "..."
        },
        "images_meta": [
            {
                "filename": "...",
                "batch": "...",
                "plate": "...",
                "well": "...",
                "col": ...,
                "row": ...,
                "site": ...,
                "channel": "..."
            },
            ...
        ]
    }

    Returns:
        Dict with 'meta' and 'images_meta' keys
    """
    try:
        with open(json_path, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"❌ ERROR: Metadata JSON file not found: {json_path}", file=sys.stderr)
        raise
    except json.JSONDecodeError as e:
        print(f"❌ ERROR: Failed to parse JSON from {json_path}", file=sys.stderr)
        print(f"   {e}", file=sys.stderr)
        raise

    # Validate structure
    if 'meta' not in data:
        raise ValueError("JSON must contain 'meta' key")
    if 'images_meta' not in data:
        raise ValueError("JSON must contain 'images_meta' key")

    meta = data['meta']
    images_meta = data['images_meta']

    # Validate meta has required fields
    required_meta_fields = ['batch', 'plate', 'channel']
    missing_meta_fields = [f for f in required_meta_fields if f not in meta]
    if missing_meta_fields:
        raise ValueError(f"meta missing required fields: {', '.join(missing_meta_fields)}")

    # Validate images_meta is a list
    if not isinstance(images_meta, list):
        raise ValueError("images_meta must be a list")

    if not images_meta:
        raise ValueError("images_meta list is empty")

    # Validate each image metadata has required fields
    required_image_fields = ['filename', 'batch', 'plate', 'well', 'col', 'row', 'site', 'channel']
    for idx, img in enumerate(images_meta):
        missing_fields = [f for f in required_image_fields if f not in img]
        if missing_fields:
            raise ValueError(
                f"images_meta[{idx}] missing required fields: {', '.join(missing_fields)}"
            )

    print(f"✓ Successfully loaded metadata for {len(images_meta)} images", file=sys.stderr)

    return data


def generate_csv_rows(meta: Dict, images_meta: List[Dict]) -> List[Dict]:
    """
    Generate CSV rows from metadata.

    Creates one row per image in tall format with columns:
    - FileName_{channel}
    - Metadata_Batch
    - Metadata_Plate
    - Metadata_Well
    - Metadata_Col
    - Metadata_Row
    - Metadata_Site

    No Frame or Series columns for illumination correction.

    Args:
        meta: Shared metadata dict
        images_meta: List of per-image metadata dicts

    Returns:
        List of row dicts
    """
    channel = meta['channel']
    rows = []

    for img in images_meta:
        row = {
            f'FileName_Orig{channel}': img['filename'],
            'Metadata_Batch': img['batch'],
            'Metadata_Plate': img['plate'],
            'Metadata_Well': img['well'],
            'Metadata_Col': img['col'],
            'Metadata_Row': img['row'],
            'Metadata_Site': img['site']
        }
        rows.append(row)

    print(f"✓ Generated {len(rows)} CSV rows", file=sys.stderr)

    return rows


def write_csv(rows: List[Dict], output_file: str, channel: str):
    """
    Write rows to CSV with proper column ordering.

    Column order (fixed):
    1. FileName_{channel}
    2. Metadata_Batch
    3. Metadata_Plate
    4. Metadata_Well
    5. Metadata_Col
    6. Metadata_Row
    7. Metadata_Site

    Args:
        rows: List of row dicts
        output_file: Output CSV file path
        channel: Channel name for FileName column
    """
    if not rows:
        raise ValueError("No rows to write - cannot create empty CSV")

    # Define column order (fixed)
    fieldnames = [
        f'FileName_Orig{channel}',
        'Metadata_Batch',
        'Metadata_Plate',
        'Metadata_Well',
        'Metadata_Col',
        'Metadata_Row',
        'Metadata_Site'
    ]

    print(f"✓ Writing CSV with columns: {', '.join(fieldnames)}", file=sys.stderr)

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
        description='Generate load_data.csv for CellProfiler illumination calculation from JSON metadata'
    )
    parser.add_argument(
        '--metadata-json',
        required=True,
        help='Path to metadata JSON file'
    )
    parser.add_argument(
        '--output',
        default='load_data.csv',
        help='Output CSV file path (default: load_data.csv)'
    )

    args = parser.parse_args()

    print(f"\n{'='*60}", file=sys.stderr)
    print(f"CellProfiler Illumination Calculation CSV Generator", file=sys.stderr)
    print(f"{'='*60}", file=sys.stderr)
    print(f"Metadata JSON: {args.metadata_json}", file=sys.stderr)
    print(f"Output file: {args.output}", file=sys.stderr)
    print(f"{'='*60}\n", file=sys.stderr)

    try:
        # Read and validate metadata JSON
        print(f"Step 1/3: Reading metadata JSON...", file=sys.stderr)
        data = read_metadata_json(args.metadata_json)
        meta = data['meta']
        images_meta = data['images_meta']

        # Generate rows
        print(f"\nStep 2/3: Generating CSV rows...", file=sys.stderr)
        rows = generate_csv_rows(meta, images_meta)

        # Write CSV
        print(f"\nStep 3/3: Writing CSV file...", file=sys.stderr)
        write_csv(rows, args.output, meta['channel'])

        print(f"\n{'='*60}", file=sys.stderr)
        print(f"✓ SUCCESS: CSV generation completed", file=sys.stderr)
        print(f"{'='*60}\n", file=sys.stderr)

        return 0

    except FileNotFoundError as e:
        print(f"\n❌ ERROR: File not found", file=sys.stderr)
        print(f"   {e}", file=sys.stderr)
        return 1
    except json.JSONDecodeError as e:
        print(f"\n❌ ERROR: JSON parsing error", file=sys.stderr)
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
    except Exception as e:
        print(f"\n❌ ERROR: Unexpected error occurred", file=sys.stderr)
        print(f"   {type(e).__name__}: {e}", file=sys.stderr)
        import traceback
        print(f"\nTraceback:", file=sys.stderr)
        traceback.print_exc()
        return 1


if __name__ == '__main__':
    sys.exit(main())
