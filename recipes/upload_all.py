#!/usr/bin/env python3
"""
Upload all conda packages from output/linux-64/ directory to prefix.dev

Environment variables (optional):
  ROCK_THE_CONDA_TARGET_CHANNEL  - Override the default channel (default: rock-the-conda)
  ROCK_THE_CONDA_PREFIX_DEV_TOKEN - If set, pass --api-key to pixi upload
                                    instead of relying on pixi auth
"""

import os
import subprocess
import sys
from pathlib import Path

DEFAULT_CHANNEL = "rock-the-conda"


def main():
    # Define the output directory
    output_dir = Path("./output/linux-64")

    # Check if directory exists
    if not output_dir.exists():
        print(f"Error: Directory {output_dir} does not exist")
        sys.exit(1)

    # Find all .conda files
    conda_packages = list(output_dir.glob("*.conda"))

    if not conda_packages:
        print(f"No .conda packages found in {output_dir}")
        sys.exit(0)

    print(f"Found {len(conda_packages)} packages to upload")

    # Channel (overridable via env var)
    # ROCK_THE_CONDA_TARGET_CHANNEL can be a full URL like https://prefix.dev/rock-the-conda-strix
    # or just a channel name like rock-the-conda-strix. Extract the channel name for pixi upload.
    channel_raw = os.environ.get("ROCK_THE_CONDA_TARGET_CHANNEL", DEFAULT_CHANNEL)
    if "/" in channel_raw:
        channel = channel_raw.rstrip("/").rsplit("/", 1)[-1]
    else:
        channel = channel_raw

    # Optional API key (overrides default pixi auth)
    api_key = os.environ.get("ROCK_THE_CONDA_PREFIX_DEV_TOKEN")

    if api_key:
        print(f"Using explicit API key for channel '{channel}'")
    else:
        print(f"Using pixi auth credentials for channel '{channel}'")

    # Upload each package
    failed_uploads = []
    for i, package in enumerate(conda_packages, 1):
        print(f"\n[{i}/{len(conda_packages)}] Uploading {package.name}...")

        cmd = ["pixi", "upload", "prefix", "--verbose", "--channel", channel]
        if api_key:
            cmd.extend(["--api-key", api_key])
        cmd.append(str(package))

        try:
            result = subprocess.run(
                cmd,
                check=True,
                capture_output=True,
                text=True,
            )
            print(f"✓ Successfully uploaded {package.name}")
            if result.stdout:
                print(result.stdout)
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to upload {package.name}")
            print(f"Error: {e.stderr}")
            failed_uploads.append(package.name)
        except FileNotFoundError:
            print("Error: 'pixi' command not found. Please ensure pixi is installed and in PATH")
            sys.exit(1)

    # Summary
    print("\n" + "=" * 60)
    print(f"Upload complete: {len(conda_packages) - len(failed_uploads)}/{len(conda_packages)} successful")

    if failed_uploads:
        print(f"\nFailed uploads ({len(failed_uploads)}):")
        for pkg in failed_uploads:
            print(f"  - {pkg}")
        sys.exit(1)
    else:
        print("All packages uploaded successfully!")
        sys.exit(0)


if __name__ == "__main__":
    main()
