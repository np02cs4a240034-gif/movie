$ErrorActionPreference = 'Stop'


$port = if ($env:PORT) { try { [int]$env:PORT } catch { 8080 } } else { 8080 }

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "REST server running at http://localhost:$port/"



function SendFile($response, $statusCode, $filePath, $contentType) {
    if (-not (Test-Path $filePath)) {
        $response.StatusCode = 404
        $response.Close()
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $response.ContentType = $contentType
    $response.StatusCode = $statusCode
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
}

function Read-MoviesFile {
    if (-not (Test-Path './movies.json')) {
        return [pscustomobject]@{ movies = @() }
    }
    $json = Get-Content -Path './movies.json' -Raw
    return $json | ConvertFrom-Json
}

function Write-MoviesFile($data) {
    $json = $data | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText('./movies.json', $json)
}

function SendJson($response, $statusCode, $payload) {
    $json = $payload | ConvertTo-Json -Depth 10
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response.ContentType = "application/json"
    $response.StatusCode = $statusCode
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
}

function SendError($response, $statusCode, $code, $message) {
    SendJson $response $statusCode @{ success = $false; error = @{ code = $code; message = $message } }
}

# ---------------------------------------------------------
# Main Loop
# ---------------------------------------------------------
while ($true) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    # CORS
    $response.Headers.Add("Access-Control-Allow-Origin","*")
    $response.Headers.Add("Access-Control-Allow-Headers","Content-Type")
    $response.Headers.Add("Access-Control-Allow-Methods","GET,POST,PUT,DELETE,OPTIONS")

    if ($request.HttpMethod -eq "OPTIONS") {
        $response.StatusCode = 204
        $response.Close()
        continue
    }

    $path = $request.Url.AbsolutePath.TrimEnd("/")
    $method = $request.HttpMethod

    try {
        switch -Regex ($path) {

# ---------------------------------------------------------
# Static Routes
# ---------------------------------------------------------
            '^/$' {
                if ($method -eq "GET") {
                    SendFile $response 200 "./index.html" "text/html; charset=utf-8"
                } else { $response.StatusCode = 405; $response.Close() }
                break
            }

            '^/index\.html$' {
                if ($method -eq "GET") {
                    SendFile $response 200 "./index.html" "text/html; charset=utf-8"
                } else { $response.StatusCode = 405; $response.Close() }
                break
            }

            '^/script\.js$' {
                if ($method -eq "GET") {
                    SendFile $response 200 "./script.js" "application/javascript; charset=utf-8"
                } else { $response.StatusCode = 405; $response.Close() }
                break
            }

            '^/movies\.json$' {
                if ($method -eq "GET") {
                    SendFile $response 200 "./movies.json" "application/json; charset=utf-8"
                } else { $response.StatusCode = 405; $response.Close() }
                break
            }

# ---------------------------------------------------------
# HEALTH CHECK
# ---------------------------------------------------------
            '^/health$' {
                if ($method -eq "GET") {
                    SendJson $response 200 @{ status = "ok"; port = $port }
                } else { $response.StatusCode = 405; $response.Close() }
                break
            }

# ---------------------------------------------------------
# /movies  (GET + POST)
# ---------------------------------------------------------
            '^/movies$' {
                switch ($method) {

                    "GET" {
                        $data = Read-MoviesFile
                        SendJson $response 200 $data.movies
                    }

                    "POST" {
                        $body = (New-Object IO.StreamReader $request.InputStream).ReadToEnd()
                        $newMovie = $body | ConvertFrom-Json

                        if (-not $newMovie.title -or -not $newMovie.year) {
                            SendError $response 400 "validation_failed" "title and year required"
                            break
                        }

                        $data = Read-MoviesFile
                        $ids = @($data.movies | ForEach-Object { $_.id })
                        $newId = if ($ids.Count -gt 0) { ($ids | Measure-Object -Maximum).Maximum + 1 } else { 1 }

                        $newMovie | Add-Member -NotePropertyName "id" -NotePropertyValue $newId
                        $data.movies += $newMovie
                        Write-MoviesFile $data

                        SendJson $response 201 $newMovie
                    }

                    default {
                        $response.StatusCode = 405
                        $response.Close()
                    }
                }
                break
            }

# ---------------------------------------------------------
# /movies/{id}  (GET, PUT, DELETE)
# ---------------------------------------------------------
            '^/movies/([0-9]+)$' {
                $id = [int]([regex]::Match($path, '^/movies/([0-9]+)$').Groups[1].Value)
                $data = Read-MoviesFile
                $movie = $data.movies | Where-Object { $_.id -eq $id }

                switch ($method) {

                    "GET" {
                        if ($null -eq $movie) { $response.StatusCode = 404; $response.Close(); break }
                        SendJson $response 200 $movie
                    }

                    "PUT" {
                        $body = (New-Object IO.StreamReader $request.InputStream).ReadToEnd()
                        $updated = $body | ConvertFrom-Json
                        $updated.id = $id

                        for ($i=0; $i -lt $data.movies.Count; $i++) {
                            if ($data.movies[$i].id -eq $id) {
                                $data.movies[$i] = $updated
                                break
                            }
                        }

                        Write-MoviesFile $data
                        SendJson $response 200 $updated
                    }

                    "DELETE" {
                        $before = $data.movies.Count
                        $data.movies = @($data.movies | Where-Object { $_.id -ne $id })

                        if ($data.movies.Count -eq $before) { $response.StatusCode = 404; $response.Close(); break }

                        Write-MoviesFile $data
                        $response.StatusCode = 204
                        $response.Close()
                    }

                    default {
                        $response.StatusCode = 405
                        $response.Close()
                    }
                }
                break
            }

# ---------------------------------------------------------
# 404
# ---------------------------------------------------------
            Default {
                $response.StatusCode = 404
                $response.Close()
            }
        }
    }
    catch {
        SendJson $response 500 @{ error = $_.Exception.Message }
    }
}
