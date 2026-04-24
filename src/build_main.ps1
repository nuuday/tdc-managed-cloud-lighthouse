$scriptDir = $PSScriptRoot

$sourceFile = Join-Path $scriptDir "main.bicep"
$targetFile = Join-Path (Split-Path -Parent $scriptDir) "deploy-lighthouse-to-managementgroup.json"

az bicep build --file $sourceFile --outfile $targetFile
