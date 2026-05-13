#!/bin/bash

# Get directory of the executing script
scriptDir=$(cd "$(dirname "$0")" || exit 1; pwd)

# Build source and target paths
sourceFile="$scriptDir/main.bicep"
targetFile="$(dirname "$scriptDir")/deploy-lighthouse-to-managementgroup.json"

# Run bicep build
az bicep build --file "$sourceFile" --outfile "$targetFile"
