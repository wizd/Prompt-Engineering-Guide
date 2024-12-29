# 使用脚本所在目录作为基准路径
$scriptDir = $PSScriptRoot
$inputDir = Join-Path $scriptDir "input"
$outputDir = Join-Path $scriptDir "output"
New-Item -ItemType Directory -Force -Path $inputDir
New-Item -ItemType Directory -Force -Path $outputDir

# 清理input目录
Get-ChildItem -Path $inputDir -Recurse | Remove-Item -Force -Recurse

Write-Host "第1步：转换所有.zh.mdx文件到markdown..."

# 使用Join-Path构建pages目录的完整路径
$pagesDir = Join-Path $scriptDir "..\pages"
$mdxFiles = Get-ChildItem -Path $pagesDir -Filter "*.zh.mdx" -Recurse

foreach ($mdxFile in $mdxFiles) {
    # 修正相对路径计算
    $relativePath = $mdxFile.FullName.Replace($pagesDir + "\", "")
    $targetDir = Join-Path $inputDir (Split-Path $relativePath)
    $targetFile = Join-Path $inputDir ($relativePath -replace "\.mdx$", ".md")
    
    # 创建目标目录
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    
    # 使用npx mdx-to-md进行转换
    Write-Host "正在转换: $relativePath"
    npx mdx-to-md $mdxFile.FullName $targetFile
}

Write-Host "`n第2步：生成epub文件..."

# 获取所有转换后的md文件
$mdFiles = Get-ChildItem -Path $inputDir -Filter "*.md" -Recurse | Sort-Object FullName

# 构建pandoc命令参数
$pandocArgs = @()
foreach ($mdFile in $mdFiles) {
    $pandocArgs += $mdFile.FullName
}

# 添加输出参数
$pandocArgs += "-o"
$pandocArgs += "$outputDir/PromptEngineering-zh.epub"
$pandocArgs += "--metadata"
$pandocArgs += "title=Prompt Engineering 指南"
$pandocArgs += "--metadata"
$pandocArgs += "author=DAIR.AI"
$pandocArgs += "--metadata"
$pandocArgs += "lang=zh-CN"
$pandocArgs += "--toc"
$pandocArgs += "--toc-depth=2"
$pandocArgs += "--epub-chapter-level=2"
$pandocArgs += "--css=../pages/style.css"

Write-Host "正在生成epub文件..."
Write-Host "执行命令: pandoc $($pandocArgs -join ' ')"

try {
    $pandocProcess = Start-Process -FilePath "pandoc" -ArgumentList $pandocArgs -Wait -NoNewWindow -PassThru
    
    if ($pandocProcess.ExitCode -eq 0) {
        Write-Host "epub文件生成成功！文件保存在: $outputDir/PromptEngineering-zh.epub"
        
        # 检查epub文件是否实际生成
        if (Test-Path "$outputDir/PromptEngineering-zh.epub") {
            Write-Host "epub文件已成功创建。"
        } else {
            Write-Error "epub文件未能成功创建。"
        }
    } else {
        Write-Error "Pandoc 转换过程失败，退出代码: $($pandocProcess.ExitCode)"
    }
} catch {
    Write-Error "生成epub时出错: $_"
}
