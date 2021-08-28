# build-model-manifest-action

A GitHub action that generates a package model from partials and a manifest of git commit hashes of that model.

## Status

This action is in active development, all aspects subject to change and no expectation that this will work for anyone for any purpose.

## Overview

This action is intended to be used to generate package repositories from models which describe package snapshots in terms of git semantics (url, branch, commit).  

Two files are generated if this action is successful:
* A model file consisting of the merged `common-model-path` and `custom-model-path` files passed as inputs, with a path specified by input `generated-model-file`.
* A manifest file consisting of the model package name, the git branch, and the git commit hash for each package specified in the generated model.  This file can be committed to git and is a way of detecting changes across the entire set of packages.

## Package Model Schema

Manifest and package generation use a package model as a primary source.  A package model is a JSON document with root objects `description` and `packages` as below:

```json
{
  "description": {
    "title": "A one line description of what this model is for"
  },
  "packages": {
    "some-new-package-name": {
      "source": "some-package-git-url",
      "branch": "some-branch-name"
    },
    "existing-package-but-different-source": {
      "name": "some-distro-specific-name",
      "upstreamTarball": "some-url-to-tar.gz"
    },
    "an-unneeded-package": null
  }
}
```

## Usage Example

```yaml
      - id: generate-model-manifest
        uses: kgilmer/build-model-manifest-action@v0.3
        with:
          common-model-path: custom.json
          custom-model-path: common.json
          generated-manifest-path: manifest.txt
          generated-model-path: /tmp/model.json
```