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
$pagesDir = Join-Path $scriptDir ".\pages"
$mdxFiles = Get-ChildItem -Path $pagesDir -Filter "*.zh.mdx" -Recurse
if (-not $mdxFiles) {
    Write-Warning "未找到任何.zh.mdx文件在路径: $pagesDir"
    exit
}

foreach ($mdxFile in $mdxFiles) {
    try {
        # 修复相对路径计算逻辑
        $fullPath = $mdxFile.FullName
        $pagesPath = (Resolve-Path $pagesDir).Path
        
        if ($fullPath.StartsWith($pagesPath)) {
            $relativePath = $fullPath.Substring($pagesPath.Length).TrimStart('\')
        } else {
            Write-Warning "文件不在pages目录中: $fullPath"
            continue
        }
        
        $targetDir = Join-Path $inputDir (Split-Path $relativePath)
        $targetFile = Join-Path $inputDir ($relativePath -replace "\.mdx$", ".md")
        
        # 确保目标目录存在
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        }
        
        # 使用npx mdx-to-md进行转换，添加错误处理
        Write-Host "正在转换: $relativePath"
        $env:NODE_ENV = "production"  # 设置 Node 环境为生产环境
        $result = npx mdx-to-md $mdxFile.FullName $targetFile --platform=node --external:components/* 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "转换失败: $relativePath`n$result"
            
            # 尝试创建一个简单的 markdown 文件作为备选
            Get-Content $mdxFile.FullName | 
                Where-Object { -not $_.Contains('import ') -and -not $_.Contains('<ContentFileNames') } |
                Set-Content $targetFile
        }

        # 处理生成的markdown文件内容
        $content = Get-Content $targetFile
        $newContent = $content | ForEach-Object {
            if ($_ -eq '---') {
                # 如果行只包含 ---, 则删除该行（返回空）
                return
            }
            elseif ($_ -match '^---(.+)') {
                # 如果行以 --- 开头，删除 --- 并保留剩余内容
                return $matches[1].TrimStart()
            }
            else {
                # 其他行保持不变
                return $_
            }
        }
        
        # 将处理后的内容写回文件
        $newContent | Set-Content $targetFile -Force

    }
    catch {
        Write-Error "处理文件时出错: $($mdxFile.FullName)`n$_"
        continue
    }
}

Write-Host "`n第2步：生成epub文件..."

# 添加图片处理逻辑
$imagesDir = Join-Path $scriptDir ".\pages\img"
$targetImagesDir = Join-Path $inputDir "img"

# 复制图片文件夹
if (Test-Path $imagesDir) {
    Write-Host "复制图片资源..."
    Copy-Item -Path $imagesDir -Destination $targetImagesDir -Recurse -Force
}

# 更新markdown文件中的图片路径
$mdFiles = Get-ChildItem -Path $inputDir -Filter "*.md" -Recurse
foreach ($mdFile in $mdFiles) {
    $content = Get-Content $mdFile.FullName -Raw
    # 将 ../../img 替换为 ./img
    $content = $content -replace '\.\./\.\./img', './img'
    $content | Set-Content $mdFile.FullName -Force
}

# 获取所有转换后的md文件
$mdFiles = Get-ChildItem -Path $inputDir -Filter "*.md" -Recurse | Sort-Object FullName

# 构建pandoc命令参数
$pandocArgs = @()
foreach ($mdFile in $mdFiles) {
    # 使用双引号包裹文件路径，以处理包含空格的路径
    $pandocArgs += "`"$($mdFile.FullName)`""
}

# pandoc 命令参数添加资源目录
$pandocArgs += "--resource-path=`"$inputDir`""

# 修改输出文件参数，确保路径被正确引用
$outputFile = Join-Path $outputDir "PromptEngineering-zh.epub"
$pandocArgs += "-o"
$pandocArgs += "`"$outputFile`""
$pandocArgs += "--metadata"
$pandocArgs += "title=`"Prompt Engineering 指南`""
$pandocArgs += "--metadata"
$pandocArgs += "author=DAIR.AI"
$pandocArgs += "--metadata"
$pandocArgs += "lang=zh-CN"
$pandocArgs += "--toc"
$pandocArgs += "--toc-depth=2"
$pandocArgs += "--epub-chapter-level=2"
$pandocArgs += "--css=./pages/style.css"

Write-Host "正在生成epub文件..."
Write-Host "执行命令: pandoc $($pandocArgs -join ' ')"

try {
    # 构建完整的命令字符串
    $pandocCmd = "pandoc $($pandocArgs -join ' ')"
    
    # 使用 Invoke-Expression 执行命令
    $result = Invoke-Expression $pandocCmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "epub文件生成成功！文件保存在: $outputFile"
        
        if (Test-Path $outputFile) {
            Write-Host "epub文件已成功创建。"
        } else {
            Write-Error "epub文件未能成功创建。"
        }
    } else {
        Write-Error "Pandoc 转换过程失败，退出代码: $LASTEXITCODE"
    }
} catch {
    Write-Error "生成epub时出错: $_"
}
