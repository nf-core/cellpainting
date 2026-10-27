#!/usr/bin/env python3
"""
Generate load_data.csv for CellProfiler illumination calculation.

Reads metadata JSON from Nextflow and generates a CSV with:
- FileName_Orig{channel} column
- Metadata columns (Batch, Plate, Well, Col, Row, Site)

Uses only Python standard library.
"""

import argparse
import csv
import json
import sys


def read_metadata_json(json_path):
    """Read and validate metadata JSON file."""
    with open(json_path, 'r') as f:
        data = json.load(f)

    if 'meta' not in data:
        raise ValueError("JSON must contain 'meta' key")
    if 'images' not in data:
        raise ValueError("JSON must contain 'images' key")
    if not data['images']:
        raise ValueError("images list is empty")

    return data


def generate_csv(data, output_file):
    """Generate load_data.csv from metadata."""
    meta = data['meta']
    images = sorted(data['images'], key=lambda img: (img['well'], img['site'], img['filename']))
    channel = meta['channel']

    fieldnames = [
        f'FileName_Orig{channel}',
        'Metadata_Batch',
        'Metadata_Plate',
        'Metadata_Well',
        'Metadata_Col',
        'Metadata_Row',
        'Metadata_Site',
    ]

    with open(output_file, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for img in images:
            writer.writerow({
                f'FileName_Orig{channel}': img['filename'],
                'Metadata_Batch': img['batch'],
                'Metadata_Plate': img['plate'],
                'Metadata_Well': img['well'],
                'Metadata_Col': img['col'],
                'Metadata_Row': img['row'],
                'Metadata_Site': img['site'],
            })

    print(f"Generated {output_file} with {len(images)} rows", file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(
        description='Generate load_data.csv for CellProfiler illumination calculation'
    )
    parser.add_argument('--metadata', required=True, help='Path to metadata JSON file')
    parser.add_argument('--output', default='load_data.csv', help='Output CSV file path')

    args = parser.parse_args()

    data = read_metadata_json(args.metadata)
    generate_csv(data, args.output)


if __name__ == '__main__':
    main()
