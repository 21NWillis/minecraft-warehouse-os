# consult.ps1 - outside-model consult via OpenRouter (the org chart:
# outside models ideate, Claude holds doctrine and commits).
# Key: env OPENROUTER_API_KEY (user registry) or C:\Users\<you>\tools\openrouter.key
# NEVER put the key in this repo.
#
# Usage:
#   .\tools\consult.ps1 -Model moonshotai/kimi-k3 -Files planning\atm10_translation.md,QUIRKS.md -Prompt "Fresh eyes: what are we sleeping on?" -Out planning\consult_raw.md
#   .\tools\consult.ps1 -ListModels kimi        # discover model ids
param(
  [string]$Model = "deepseek/deepseek-v4-pro-0813",
  [string[]]$Files = @(),
  [string]$Prompt = "",
  [string]$System = "You are an outside consultant reviewing planning documents for a Minecraft automation project. Be concrete, cite the doc you are reacting to, and separate 'verified by the docs' from 'my speculation'. The house model holds doctrine; your job is ideas it might be sleeping on.",
  [string]$Out = "",
  [int]$MaxTokens = 16000,
  [string]$ReasoningEffort = "",   # low|medium|high - bound a reasoning model's thinking budget
  [string]$ListModels = ""
)

$ErrorActionPreference = "Stop"

$key = $env:OPENROUTER_API_KEY
if (-not $key) { $key = [Environment]::GetEnvironmentVariable("OPENROUTER_API_KEY", "User") }
if (-not $key -and (Test-Path "$env:USERPROFILE\tools\openrouter.key")) {
  $key = (Get-Content "$env:USERPROFILE\tools\openrouter.key" -Raw).Trim()
}
if (-not $key) { throw "no OPENROUTER_API_KEY found (env var or ~\tools\openrouter.key)" }

$headers = @{ Authorization = "Bearer $key"; "Content-Type" = "application/json" }

if ($ListModels) {
  $models = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/models"
  $models.data | Where-Object { $_.id -match $ListModels } | ForEach-Object {
    "{0}  in:{1} out:{2}" -f $_.id, $_.pricing.prompt, $_.pricing.completion
  }
  exit 0
}

if (-not $Prompt) { throw "need -Prompt (or -ListModels)" }

$docBlock = ""
foreach ($f in $Files) {
  if (-not (Test-Path $f)) { throw "missing file: $f" }
  $body = Get-Content $f -Raw
  $docBlock += "`n`n===== FILE: $f =====`n$body"
}

$userMsg = $Prompt
if ($docBlock) { $userMsg = $Prompt + "`n`nDocuments follow." + $docBlock }

$payloadTable = @{
  model      = $Model
  max_tokens = $MaxTokens
  messages   = @(
    @{ role = "system"; content = $System },
    @{ role = "user";   content = $userMsg }
  )
}
if ($ReasoningEffort) { $payloadTable.reasoning = @{ effort = $ReasoningEffort } }
$payload = $payloadTable | ConvertTo-Json -Depth 6

$bytes = [System.Text.Encoding]::UTF8.GetBytes($payload)
$resp = Invoke-RestMethod -Uri "https://openrouter.ai/api/v1/chat/completions" -Method Post -Headers $headers -Body $bytes

$msg = $resp.choices[0].message
$text = $msg.content
$usage = $resp.usage
Write-Host ("--- {0} | prompt {1} tok, completion {2} tok | finish: {3}" -f $Model, $usage.prompt_tokens, $usage.completion_tokens, $resp.choices[0].finish_reason)
if ((-not $text) -and $msg.reasoning) {
  Write-Warning "content empty but reasoning present - model spent its budget thinking. Raise -MaxTokens or set -ReasoningEffort low."
  $text = "[NO FINAL ANSWER - reasoning trace follows]`n`n" + $msg.reasoning
}

if ($Out) {
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) $Out), $text, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "written: $Out"
} else {
  $text
}
