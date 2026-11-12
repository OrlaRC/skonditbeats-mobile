# Práctica 11 · Abre el informe en Word, actualiza el índice y los campos, guarda y exporta a PDF.
# Uso: powershell -ExecutionPolicy Bypass -File tool\p11\word_pdf.ps1 "<ruta .docx>"
param([Parameter(Mandatory = $true)][string]$Docx)
$ErrorActionPreference = 'Stop'
$ruta = (Resolve-Path $Docx).Path
$pdf = [IO.Path]::ChangeExtension($ruta, '.pdf')
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$word.DisplayAlerts = 0
try {
  $doc = $word.Documents.Open($ruta)
  foreach ($toc in $doc.TablesOfContents) { $toc.Update() }
  $doc.Fields.Update() | Out-Null
  $doc.Save()
  $doc.ExportAsFixedFormat($pdf, 17)   # 17 = wdExportFormatPDF
  "Páginas: $($doc.ComputeStatistics(2))"
  $doc.Close()
  "PDF: $pdf"
} finally {
  $word.Quit()
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word)
}
