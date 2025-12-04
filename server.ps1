$ErrorActionPreference = 'Stop'

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://localhost:3000/')
$listener.Start()
Write-Host 'REST server running at http://localhost:3000/'

function Read-MoviesFile {
  if (-not (Test-Path -Path './movies.json')) {
    return [pscustomobject]@{ movies = @() }
  }
  $json = Get-Content -Path './movies.json' -Raw
  return $json | ConvertFrom-Json
}

function Write-MoviesFile($data) {
  $json = $data | ConvertTo-Json -Depth 10
  Set-Content -Path './movies.json' -Value $json -Encoding UTF8
}

function SendJson($response, $statusCode, $payload) {
  $json = $payload | ConvertTo-Json -Depth 10
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  $response.ContentType = 'application/json'
  $response.StatusCode = $statusCode
  $response.OutputStream.Write($bytes, 0, $bytes.Length)
  $response.Close()
}

function SendError($response, $statusCode, $code, $message) {
  $payload = @{ success = $false; error = @{ code = $code; message = $message } }
  SendJson $response $statusCode $payload
}

while ($true) {
  $context = $listener.GetContext()
  $request = $context.Request
  $response = $context.Response

  $response.Headers.Add('Access-Control-Allow-Origin','*')
  $response.Headers.Add('Access-Control-Allow-Headers','Content-Type')
  $response.Headers.Add('Access-Control-Allow-Methods','GET,POST,PUT,DELETE,OPTIONS')

  if ($request.HttpMethod -eq 'OPTIONS') {
    $response.StatusCode = 204
    $response.Close()
    continue
  }

  $path = $request.Url.AbsolutePath.TrimEnd('/')
  $method = $request.HttpMethod

  try {
    switch -Regex ($path) {
      '^/movies$' {
        switch ($method) {
          'GET' {
            $data = Read-MoviesFile
            $items = @($data.movies)
            $q = $request.QueryString['q']
            if ($q) {
              $ql = $q.ToLower()
              $items = @($items | Where-Object { ($_.title -and $_.title.ToString().ToLower().Contains($ql)) -or ($_.genre -and $_.genre.ToString().ToLower().Contains($ql)) })
            }
            $sort = if ($request.QueryString['sort']) { $request.QueryString['sort'] } else { $request.QueryString['_sort'] }
            $order = if ($request.QueryString['order']) { $request.QueryString['order'] } else { $request.QueryString['_order'] }
            if ($sort) {
              $desc = ($order -eq 'desc')
              $items = @($items | Sort-Object -Property $sort -Descending:$desc)
            }
            $total = $items.Count
            $page = if ($request.QueryString['page']) { $request.QueryString['page'] } else { $request.QueryString['_page'] }
            $limit = if ($request.QueryString['limit']) { $request.QueryString['limit'] } else { $request.QueryString['_limit'] }
            if ($page -and $limit) {
              try { $p = [int]$page } catch { $p = 1 }
              if ($p -lt 1) { $p = 1 }
              try { $l = [int]$limit } catch { $l = $total }
              if ($l -lt 1) { $l = $total }
              $skip = ($p - 1) * $l
              $items = @($items | Select-Object -Skip $skip -First $l)
              $response.Headers.Add('X-Total-Count', [string]$total)
            }
            $envelope = $request.QueryString['envelope']
            if ($envelope -eq 'true') {
              $meta = @{ total = $total; page = if ($page) { [int]$page } else { 1 }; limit = if ($limit) { [int]$limit } else { $total }; sort = $sort; order = if ($order) { $order } else { 'asc' } }
              SendJson $response 200 @{ success = $true; data = $items; meta = $meta }
            } else {
              SendJson $response 200 $items
            }
          }
          'POST' {
            $reader = [System.IO.StreamReader]::new($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
            $newMovie = $body | ConvertFrom-Json
            $titleOk = ($newMovie.title -and $newMovie.title.ToString().Trim().Length -gt 0)
            $yearOk = $false
            try { $tmpYear = [int]$newMovie.year; $yearOk = $true } catch { $yearOk = $false }
            if (-not $titleOk -or -not $yearOk) { SendError $response 400 'validation_failed' 'title and integer year required'; break }
            $data = Read-MoviesFile
            $ids = @($data.movies | ForEach-Object { $_.id })
            $nextId = if ($ids.Count -gt 0) { [int]([System.Linq.Enumerable]::Max([int[]]$ids)) + 1 } else { 1 }
            $newMovie | Add-Member -NotePropertyName 'id' -NotePropertyValue $nextId -Force
            $data.movies += $newMovie
            Write-MoviesFile $data
            $response.Headers.Add('Location', "http://localhost:3000/movies/$nextId")
            SendJson $response 201 $newMovie
          }
          Default {
            $response.StatusCode = 405
            $response.Close()
          }
        }
        break
      }
      '^/movies/([0-9]+)$' {
        $id = [int]([regex]::Match($path, '^/movies/([0-9]+)$').Groups[1].Value)
        $data = Read-MoviesFile
        $index = ($data.movies | ForEach-Object { $_.id }) -as [int[]]
        $match = $data.movies | Where-Object { $_.id -eq $id }
        switch ($method) {
          'GET' {
            if ($null -eq $match) { $response.StatusCode = 404; $response.Close(); break }
            SendJson $response 200 $match
          }
          'PUT' {
            $reader = [System.IO.StreamReader]::new($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Dispose()
            $updated = $body | ConvertFrom-Json
            $updated.id = $id
            $found = $false
            for ($i = 0; $i -lt $data.movies.Count; $i++) {
              if ($data.movies[$i].id -eq $id) { $data.movies[$i] = $updated; $found = $true; break }
            }
            if (-not $found) { $response.StatusCode = 404; $response.Close(); break }
            $titleOk = ($updated.title -and $updated.title.ToString().Trim().Length -gt 0)
            $yearOk = $false
            try { $tmpYear = [int]$updated.year; $yearOk = $true } catch { $yearOk = $false }
            if (-not $titleOk -or -not $yearOk) { SendError $response 400 'validation_failed' 'title and integer year required'; break }
            Write-MoviesFile $data
            SendJson $response 200 $updated
          }
          'DELETE' {
            $before = $data.movies.Count
            $data.movies = @($data.movies | Where-Object { $_.id -ne $id })
            if ($data.movies.Count -eq $before) { $response.StatusCode = 404; $response.Close(); break }
            Write-MoviesFile $data
            $response.StatusCode = 204
            $response.Close()
          }
          Default {
            $response.StatusCode = 405
            $response.Close()
          }
        }
        break
      }
      Default {
        $response.StatusCode = 404
        $response.Close()
      }
    }
  }
  catch {
    $response.StatusCode = 500
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json @{ error = $_.Exception.Message }))
    $response.ContentType = 'application/json'
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
    $response.Close()
  }
}