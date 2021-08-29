#!/bin/bash
# This script can be used to generate Debian packages and add them to a local debian repository.

# Input Parameters
if [ "$#" -lt 2 ]; then
    echo "This script prints a manifest from package repos.  It uses a package model file that describes each package."
    echo "If no package name is specified from the model, all packages are built."
    echo "Usage: build-manifest.sh <package model> <manifest file> <temp build dir> [package]"
    exit 1
fi

# Common logic

print_banner() {
    echo "***********************************************************"
    echo "** $1"
    echo "***********************************************************"
}

# Checkout
checkout() {
    if [ -z "${packageModel[source]}" ]; then 
        echo "Package model is invalid.  Model field 'source' undefined, aborting."
        exit 1
    fi

    repo_url=${packageModel[source]}
    repo_path=${repo_url##*/}
    repo_name=${repo_path%%.*}
    
    if [ -d "$BUILD_DIR/$repo_name" ]; then
        echo "Deleting existing repo, $repo_name"
        rm -Rfv "${BUILD_DIR:?}/$repo_name"
    fi

    if [ ! -d "$BUILD_DIR" ]; then 
        echo "Creating build directory $BUILD_DIR"
        mkdir -p "$BUILD_DIR" || { echo "Failed to create build dir $BUILD_DIR, aborting."; exit 1; }
    fi

    print_banner "Checking out ${packageModel[source]} into $BUILD_DIR"

    cd "$BUILD_DIR" || exit
    git clone --recursive "${packageModel[source]}" -b "${packageModel[branch]}"
    
    cd - > /dev/null 2>&1  || exit
}

sanitize_git() {
    if [ -d  ".github" ]; then 
        rm -Rf .github 
        echo "Removed $(pwd).github directory before building to appease debuild."
    fi
    if [ -d  ".git" ]; then 
        rm -Rf .git
        echo "Removed $(pwd).git directory before building to appease debuild."
    fi
}

# Stage package source in prep to build 
stage_source() {
    print_banner "Preparing source for ${packageModel[name]}"
    cd "$BUILD_DIR/${packageModel[name]}"  || exit
    full_version=$(dpkg-parsechangelog --show-field Version)
    debian_version="${full_version%-*}"
    cd "$BUILD_DIR" || exit
    
    if [ "${packageModel[upstreamTarball]}" != "" ]; then
        echo "Downloading source from ${packageModel[upstreamTarball]}..."
        wget ${packageModel[upstreamTarball]} -O ${packageModel[name]}/../${packageModel[name]}\_$debian_version.orig.tar.gz
    else
        echo "Generating source tarball from git repo."
        tar cfzv ${packageModel[name]}\_${debian_version}.orig.tar.gz --exclude .git\* --exclude debian ${packageModel[name]}/../${packageModel[name]}
    fi
}

# Build
build_src_package() {
    print_banner "Building source package ${packageModel[name]}"
    cd "$BUILD_DIR/${packageModel[name]}" || exit
    
    sanitize_git    
    sudo apt build-dep -y .
    debuild -S -sa
    cd "$BUILD_DIR" || exit
}

build_bin_package() {
    print_banner "Building binary package ${packageModel[name]}"
    cd "$BUILD_DIR/${packageModel[name]}"  || exit
    
    sanitize_git
    debuild -sa -b
    cd "$BUILD_DIR" || exit
}

cache_model() {    
    PACKAGE_MODEL_FILE="$BUILD_DIR/pkg-model.json"

    if [ -f "$PACKAGE_MODEL_FILE" ]; then 
        echo "Removing stale cache $PACKAGE_MODEL_FILE"
        rm "$PACKAGE_MODEL_FILE" || { echo "Failed to delete cache file, aborting."; exit 1; }
    fi

    cat >"$PACKAGE_MODEL_FILE"

#    while IFS= read -r line; do
#        printf '%s\n' "$line" > "$PACKAGE_MODEL_FILE"
#    done
}

# The following look extracts package objects from the model, creates a map of the values,
# and then passes that map to bash functions for processing.  The script that calls this function
# must declare a function called 'handle_package' and the model data will be provided in a map
# called 'packageModel'.
#
# For each iteration, if $PACKAGE_FILTER is defined, eval does not occur if string match of 'name' fails
#
# Model fields:
# modelDescription: Description for package model (common for all packages in model file)
# name: (Optional) Regolith name for a linux package. Default is Debian naming if exists.  May be overridden
#           by specifying property 'name' in object.  If unspecifed object key is used.
# source: SCM URL from which the package can be cloned.
# branch: branch to pull source from to build
# upstreamTarball: (optional)
read_package_model() {
    jq -rc 'delpaths([path(.[][]| select(.==null))]) | .packages | keys | .[]' < "$PACKAGE_MODEL_FILE" | while IFS='' read -r package; do
        # Set the package name and model desc
        packageModel["name"]="$package"    
        packageModel["modelDescription"]=$(jq -r ".description.title" < "$PACKAGE_MODEL_FILE" )
        # Set all kvps on the associated object
        while IFS== read -r key value; do
            packageModel["$key"]="$value"
        done < <( jq -r ".packages.\"$package\" | to_entries | .[] | .key + \"=\" + .value" < "$PACKAGE_MODEL_FILE" )

        # If a package filter was specified, match filter.
        if [[ -n "$PACKAGE_FILTER" && "$PACKAGE_FILTER" != "${packageModel[name]}" ]]; then
            continue
        fi

        # Apply functions to package model
        print_banner "handle_package(${packageModel[name]})"
        handle_package
    done
}

# Custom logic

# shellcheck disable=SC2034
MANIFEST_FILE=$(realpath "$1")
BUILD_DIR=$2
# shellcheck disable=SC2034
PACKAGE_FILTER=$3

# Print manifest
append_manifest() {    
    cd $BUILD_DIR/${packageModel[name]}
    REPO_NAME=${packageModel[name]}
    BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
    COMMIT_HASH=$(git rev-parse --short HEAD)

    echo "$REPO_NAME $BRANCH_NAME $COMMIT_HASH" >> "$MANIFEST_FILE"
}

# Verify execution environment
env_check() {
    hash git 2>/dev/null || { echo >&2 "Required command git is not found on this system. Please install it. Aborting."; exit 1; }
}

handle_package() {
    checkout
    append_manifest
}

# Main
set -e
# set -x

env_check
if [ ! -d $BUILD_DIR ]; then
    mkdir -p $BUILD_DIR
fi

print_banner "Generating package manifest $MANIFEST_FILE"

typeset -A packageModel

cache_model
read_package_model