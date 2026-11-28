; ==============================================================================
; Module: SelfUpdater.ahk
; Description: GitHub release checker, WinINet downloader, SHA-256 verifier & .exe swapper
; ==============================================================================
CompareSemVer(vA, vB) {
    cleanA := RegExReplace(Trim(String(vA)), "^[vV]")
    cleanB := RegExReplace(Trim(String(vB)), "^[vV]")
    partsA := StrSplit(cleanA, ".")
    partsB := StrSplit(cleanB, ".")
    maxLen := Max(partsA.Length, partsB.Length, 3)
    Loop maxLen {
        nA := 0
        nB := 0
        if (A_Index <= partsA.Length && RegExMatch(partsA[A_Index], "^(\d+)", &mA))
            nA := Integer(mA[1])
        if (A_Index <= partsB.Length && RegExMatch(partsB[A_Index], "^(\d+)", &mB))
            nB := Integer(mB[1])
        if (nA > nB)
            return 1
        if (nA < nB)
            return -1
    }
    return 0
}

ParseGitHubReleaseDetails(jsonStr, targetAssetName := "") {
    s := String(jsonStr)
    if (RegExMatch(s, '"tag_name"\s*:\s*"([^"]+)"', &mTag)) {
        tag := UnescapeJsonStr(mTag[1])
    } else if (RegExMatch(s, '"name"\s*:\s*"(v?\d+\.\d+\.\d+[^"]*)"', &mName)) {
        tag := UnescapeJsonStr(mName[1])
    } else {
        return { ok: false, tag: "", version: "", url: "", releaseNotes: "", assetName: "", assetUrl: "", assetSize: -1, sha256Url: "" }
    }
    ver := RegExReplace(Trim(tag), "^[vV]")
    url := ""
    if (RegExMatch(s, '"html_url"\s*:\s*"([^"]+)"', &mUrl))
        url := UnescapeJsonStr(mUrl[1])

    notes := ""
    if (RegExMatch(s, '"body"\s*:\s*"((?:\\.|[^"\\])*)"', &mBody))
        notes := Trim(UnescapeJsonStr(mBody[1]))

    wantedAsset := (targetAssetName != "") ? targetAssetName : GetDefaultWindowsAssetName()
    assetName := ""
    assetUrl := ""
    assetSize := -1
    shaUrl := ""

    for asset in _ExtractGitHubReleaseAssets(s) {
        if (StrLower(asset.name) = "sha256sums.txt") {
            shaUrl := asset.url
        } else if (StrLower(asset.name) = StrLower(wantedAsset)) {
            assetName := asset.name
            assetUrl := asset.url
            assetSize := asset.size
        }
    }

    return {
        ok: (ver != ""),
        tag: tag,
        version: ver,
        url: url,
        releaseNotes: notes,
        assetName: assetName,
        assetUrl: assetUrl,
        assetSize: assetSize,
        sha256Url: shaUrl
    }
}

ParseGitHubReleaseTag(jsonStr) {
    d := ParseGitHubReleaseDetails(jsonStr)
    return { ok: d.ok, tag: d.tag, version: d.version, url: d.url }
}

_ExtractGitHubReleaseAssets(jsonStr) {
    out := []
    if !RegExMatch(jsonStr, '"assets"\s*:\s*\[', &mArr)
        return out
    pos := mArr.Pos + mArr.Len
    totalLen := StrLen(jsonStr)
    insideStr := false
    escaped := false
    objStart := 0
    braceDepth := 0

    while (pos <= totalLen) {
        ch := SubStr(jsonStr, pos, 1)
        if (escaped) {
            escaped := false
            pos += 1
            continue
        }
        if (insideStr) {
            if (ch = "\")
                escaped := true
            else if (ch = '"')
                insideStr := false
            pos += 1
            continue
        }
        if (ch = '"') {
            insideStr := true
        } else if (ch = "]" && braceDepth == 0) {
            break
        } else if (ch = "{") {
            if (braceDepth == 0)
                objStart := pos
            braceDepth += 1
        } else if (ch = "}") {
            if (braceDepth > 0) {
                braceDepth -= 1
                if (braceDepth == 0 && objStart > 0) {
                    objStr := SubStr(jsonStr, objStart, pos - objStart + 1)
                    aName := RegExMatch(objStr, '"name"\s*:\s*"((?:\\.|[^"\\])*)"', &mN) ? Trim(UnescapeJsonStr(mN[1])) : ""
                    aUrl := RegExMatch(objStr, '"browser_download_url"\s*:\s*"((?:\\.|[^"\\])*)"', &mU) ? Trim(UnescapeJsonStr(mU[1])) : ""
                    aSize := RegExMatch(objStr, '"size"\s*:\s*(\d+)', &mS) ? Integer(mS[1]) : -1
                    if (aName != "" && aUrl != "")
                        out.Push({ name: aName, size: aSize, url: aUrl })
                    objStart := 0
                }
            }
        }
        pos += 1
    }
    return out
}

GetDefaultWindowsAssetName() {
    nm := StrLower(A_ScriptName " " A_ScriptFullPath)
    return InStr(nm, "presentersync_remote") ? "PresenterSync_Remote.exe" : "PresenterSync.exe"
}

GetCurrentUnixEpoch() {
    return DateDiff(A_NowUTC, "19700101000000", "Seconds")
}

ParseSha256SumsText(sumsText, targetFileName) {
    wanted := StrLower(Trim(String(targetFileName)))
    if (wanted = "")
        return ""
    for rawLine in StrSplit(String(sumsText), "`n", "`r") {
        if RegExMatch(rawLine, "^\s*([0-9a-fA-F]{64})\s+[* ]?(.+?)\s*$", &m) {
            digest := StrLower(m[1])
            filePart := Trim(m[2])
            filePart := RegExReplace(filePart, "^.*[/\\]", "")
            if (StrLower(filePart) = wanted)
                return digest
        }
    }
    return ""
}

VerifyPeExecutableFile(filePath, expectedSize := -1) {
    if (!FileExist(filePath))
        return { ok: false, reason: "Downloaded update file does not exist." }
    sz := FileGetSize(filePath)
    if (sz < 2)
        return { ok: false, reason: "Downloaded file is empty or truncated." }
    if (expectedSize > 0 && sz != Integer(expectedSize))
        return { ok: false, reason: "Downloaded size mismatch (" sz " != " expectedSize " bytes)." }
    f := ""
    try {
        f := FileOpen(filePath, "r")
        if (!IsObject(f))
            return { ok: false, reason: "Unable to open downloaded file for inspection." }
        hdr := Buffer(2, 0)
        if (f.RawRead(hdr, 2) < 2)
            return { ok: false, reason: "Unable to read executable header." }
        if (NumGet(hdr, 0, "UChar") != 0x4D || NumGet(hdr, 1, "UChar") != 0x5A)
            return { ok: false, reason: "Downloaded file is not a valid Windows MZ executable." }
        return { ok: true, size: sz, reason: "" }
    } catch as e {
        return { ok: false, reason: "PE header check error: " e.Message }
    } finally {
        if (IsObject(f))
            try f.Close()
    }
}

VerifyStagedExecutable(filePath, expectedSize := -1, expectedSha256 := "") {
    pe := VerifyPeExecutableFile(filePath, expectedSize)
    if (!pe.ok) {
        try FileDelete(filePath)
        return { ok: false, shaVerified: false, sha256: "", reason: pe.reason }
    }
    actualSha := HashFileSHA256_Hex(filePath)
    if (actualSha = "") {
        try FileDelete(filePath)
        return { ok: false, shaVerified: false, sha256: "", reason: "Failed to compute SHA-256 checksum." }
    }
    if (expectedSha256 != "") {
        if (StrLower(actualSha) != StrLower(Trim(expectedSha256))) {
            try FileDelete(filePath)
            return { ok: false, shaVerified: false, sha256: actualSha, reason: "SHA-256 verification failed! Expected " StrLower(expectedSha256) ", got " actualSha }
        }
        return { ok: true, shaVerified: true, sha256: actualSha, reason: "" }
    }
    return { ok: true, shaVerified: false, sha256: actualSha, reason: "" }
}

StreamHttpToFile(url, destFile, expectedSize := -1, onProgress := "", isCancelledFn := "", userAgent := "") {
    ua := (userAgent != "") ? userAgent : ("PresenterSync/" UIConstants.APP_VERSION)
    tmpFile := destFile ".tmp"
    try FileDelete(tmpFile)
    try FileDelete(destFile)

    hWinInet := 0
    hInternet := 0
    hUrl := 0
    outFile := ""
    cancelled := false

    try {
        hWinInet := DllCall("LoadLibraryW", "Str", "wininet.dll", "Ptr")
        if (!hWinInet)
            return { ok: false, cancelled: false, bytesDownloaded: 0, reason: "Unable to load wininet.dll" }

        hInternet := DllCall("wininet\InternetOpenW", "Str", ua, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt", 0, "Ptr")
        if (!hInternet)
            return { ok: false, cancelled: false, bytesDownloaded: 0, reason: "WinINet InternetOpenW failed (" A_LastError ")" }

        toBuf := Buffer(4, 0)
        NumPut("UInt", 25000, toBuf)
        DllCall("wininet\InternetSetOptionW", "Ptr", hInternet, "UInt", 2, "Ptr", toBuf, "UInt", 4) ; CONNECT_TIMEOUT
        DllCall("wininet\InternetSetOptionW", "Ptr", hInternet, "UInt", 6, "Ptr", toBuf, "UInt", 4) ; RECEIVE_TIMEOUT

        flags := 0x80000000 | 0x04000000 | 0x00400000 ; RELOAD | NO_CACHE_WRITE | KEEP_CONNECTION
        hUrl := DllCall("wininet\InternetOpenUrlW", "Ptr", hInternet, "Str", url, "Ptr", 0, "UInt", 0, "UInt", flags, "UPtr", 0, "Ptr")
        if (!hUrl)
            return { ok: false, cancelled: false, bytesDownloaded: 0, reason: "Unable to open download URL (" A_LastError ")" }

        statusBuf := Buffer(4, 0), statusLen := 4
        if (DllCall("wininet\HttpQueryInfoW", "Ptr", hUrl, "UInt", 0x20000013, "Ptr", statusBuf, "UInt*", &statusLen, "Ptr", 0)) {
            httpCode := NumGet(statusBuf, 0, "UInt")
            if (httpCode >= 400)
                return { ok: false, cancelled: false, bytesDownloaded: 0, reason: "HTTP download error " httpCode }
        }

        totalBytes := (expectedSize > 0) ? Integer(expectedSize) : -1
        clBuf := Buffer(4, 0), clLen := 4
        if (DllCall("wininet\HttpQueryInfoW", "Ptr", hUrl, "UInt", 0x20000005, "Ptr", clBuf, "UInt*", &clLen, "Ptr", 0)) {
            hdrLen := NumGet(clBuf, 0, "UInt")
            if (hdrLen > 0)
                totalBytes := hdrLen
        }

        outFile := FileOpen(tmpFile, "w")
        if (!IsObject(outFile))
            return { ok: false, cancelled: false, bytesDownloaded: 0, reason: "Cannot create temporary update file." }

        buf := Buffer(16384, 0)
        totalRead := 0
        lastUiTick := 0
        lastPct := -1

        while (true) {
            if (IsObject(isCancelledFn) && isCancelledFn.Call()) {
                cancelled := true
                break
            }
            bytesRead := 0
            okRead := DllCall("wininet\InternetReadFile", "Ptr", hUrl, "Ptr", buf, "UInt", 16384, "UInt*", &bytesRead)
            if (!okRead)
                return { ok: false, cancelled: false, bytesDownloaded: totalRead, reason: "Download interrupted (" A_LastError ")" }
            if (bytesRead == 0)
                break
            outFile.RawWrite(buf, bytesRead)
            totalRead += bytesRead
            pct := (totalBytes > 0) ? Min(100, Max(0, Floor((totalRead * 100) / totalBytes))) : 0
            nowTick := A_TickCount
            if (pct != lastPct || (nowTick - lastUiTick) >= 75) {
                lastPct := pct
                lastUiTick := nowTick
                if (IsObject(onProgress))
                    onProgress.Call(totalRead, totalBytes, pct)
                Sleep(-1)
            }
        }
        outFile.Close()
        outFile := ""

        if (cancelled) {
            try FileDelete(tmpFile)
            return { ok: false, cancelled: true, bytesDownloaded: totalRead, reason: "Download cancelled." }
        }
        if (totalBytes > 0 && totalRead != totalBytes) {
            try FileDelete(tmpFile)
            return { ok: false, cancelled: false, bytesDownloaded: totalRead, reason: "Incomplete download (" totalRead " / " totalBytes " bytes)." }
        }

        FileMove(tmpFile, destFile, 1)
        return { ok: true, cancelled: false, bytesDownloaded: totalRead, reason: "" }
    } catch as e {
        return { ok: false, cancelled: cancelled, bytesDownloaded: 0, reason: e.Message }
    } finally {
        if (IsObject(outFile))
            try outFile.Close()
        if (hUrl)
            try DllCall("wininet\InternetCloseHandle", "Ptr", hUrl)
        if (hInternet)
            try DllCall("wininet\InternetCloseHandle", "Ptr", hInternet)
        if (hWinInet)
            try DllCall("FreeLibrary", "Ptr", hWinInet)
    }
}

_FetchHttpTextSimple(url, timeoutMs := 12000, userAgent := "", acceptHeader := "") {
    ua := (userAgent != "") ? userAgent : ("PresenterSync/" UIConstants.APP_VERSION)
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.SetTimeouts(4000, 4000, timeoutMs, timeoutMs)
        req.Open("GET", url, false)
        req.SetRequestHeader("User-Agent", ua)
        if (acceptHeader != "")
            req.SetRequestHeader("Accept", acceptHeader)
        req.Send()
        if (req.Status == 200)
            return { ok: true, text: req.ResponseText, status: 200 }
        return { ok: false, text: "", status: req.Status }
    } catch as e {
        return { ok: false, text: "", status: 0, error: e.Message }
    }
}

NormalizeUpdateChannel(ch) {
    return (StrLower(Trim(String(ch))) = "nightly") ? "Nightly" : "Stable"
}

ParseGitHubCommitDetails(jsonStr) {
    s := String(jsonStr)
    sha := ""
    if (RegExMatch(s, '"sha"\s*:\s*"([0-9a-fA-F]{7,64})"', &mSha))
        sha := StrLower(mSha[1])
    if (sha = "")
        return { ok: false, sha: "", shortSha: "", date: "", url: "" }
    cDate := ""
    if (RegExMatch(s, '"committer"\s*:\s*\{[^}]*"date"\s*:\s*"([^"]+)"', &mDate))
        cDate := UnescapeJsonStr(mDate[1])
    else if (RegExMatch(s, '"date"\s*:\s*"([^"]+)"', &mDate2))
        cDate := UnescapeJsonStr(mDate2[1])
    cUrl := ""
    if (RegExMatch(s, '"html_url"\s*:\s*"([^"]+)"', &mUrl))
        cUrl := UnescapeJsonStr(mUrl[1])
    return {
        ok: true,
        sha: sha,
        shortSha: SubStr(sha, 1, 7),
        date: cDate,
        url: (cUrl != "" ? cUrl : "https://github.com/SaabithJiffry/PresenterSync/commit/" sha)
    }
}

ParseNightlyMetaJson(jsonStr) {
    s := String(jsonStr)
    ver := ""
    if (RegExMatch(s, '"version"\s*:\s*"([^"]+)"', &mV))
        ver := RegExReplace(Trim(UnescapeJsonStr(mV[1])), "^[vV]")
    vc := 0
    if (RegExMatch(s, '"androidVersionCode"\s*:\s*(\d+)', &mVc))
        vc := Integer(mVc[1])
    built := ""
    if (RegExMatch(s, '"builtAtUtc"\s*:\s*"([^"]+)"', &mB))
        built := UnescapeJsonStr(mB[1])
    return { ok: (ver != ""), version: ver, androidVersionCode: vc, builtAtUtc: built }
}

GetCurrentBinarySha256(targetExePath := "") {
    p := (targetExePath != "") ? targetExePath : (A_IsCompiled ? A_ScriptFullPath : "")
    if (p = "" || !FileExist(p))
        return ""
    return StrLower(HashFileSHA256_Hex(p))
}
ParseGitHubCommitListJson(jsonStr) {
    out := []
    str := Trim(String(jsonStr))
    if (SubStr(str, 1, 1) != "[")
        return out
    pos := 2
    totalLen := StrLen(str)
    insideStr := false
    escaped := false
    objStart := 0
    braceDepth := 0

    while (pos <= totalLen) {
        ch := SubStr(str, pos, 1)
        if (escaped) {
            escaped := false
            pos += 1
            continue
        }
        if (insideStr) {
            if (ch = "\")
                escaped := true
            else if (ch = '"')
                insideStr := false
            pos += 1
            continue
        }
        if (ch = '"') {
            insideStr := true
        } else if (ch = "]" && braceDepth == 0) {
            break
        } else if (ch = "{") {
            if (braceDepth == 0)
                objStart := pos
            braceDepth += 1
        } else if (ch = "}") {
            if (braceDepth > 0) {
                braceDepth -= 1
                if (braceDepth == 0 && objStart > 0) {
                    objStr := SubStr(str, objStart, pos - objStart + 1)
                    sha := RegExMatch(objStr, '"sha"\s*:\s*"([0-9a-fA-F]{7,64})"', &mS) ? StrLower(mS[1]) : ""
                    cDate := ""
                    if (RegExMatch(objStr, '"committer"\s*:\s*\{[^}]*"date"\s*:\s*"([^"]+)"', &mD))
                        cDate := UnescapeJsonStr(mD[1])
                    else if (RegExMatch(objStr, '"date"\s*:\s*"([^"]+)"', &mD2))
                        cDate := UnescapeJsonStr(mD2[1])
                    rawMsg := RegExMatch(objStr, '"message"\s*:\s*"((?:\\.|[^"\\])*)"', &mM) ? Trim(UnescapeJsonStr(mM[1])) : ""
                    subj := Trim(StrSplit(rawMsg, "`n", "`r")[1])
                    if (StrLen(subj) > 42)
                        subj := SubStr(subj, 1, 39) "..."
                    cUrl := RegExMatch(objStr, '"html_url"\s*:\s*"([^"]+)"', &mU) ? UnescapeJsonStr(mU[1]) : ""
                    if (sha != "") {
                        out.Push({
                            sha: sha,
                            shortSha: SubStr(sha, 1, 7),
                            dateIso: cDate,
                            dateShort: (StrLen(cDate) >= 10) ? SubStr(cDate, 1, 10) : "unknown",
                            subject: subj,
                            url: (cUrl != "" ? cUrl : "https://github.com/SaabithJiffry/PresenterSync/commit/" sha)
                        })
                    }
                    objStart := 0
                }
            }
        }
        pos += 1
    }
    return out
}

FilterPostStableNightlyCommits(commits, stableCommitSha := "", stableCommitDate := "", rawBaseOverride := "", targetAssetName := "") {
    out := []
    stSha := StrLower(Trim(String(stableCommitSha)))
    stDate := Trim(String(stableCommitDate))
    assetNm := (targetAssetName != "") ? targetAssetName : GetDefaultWindowsAssetName()

    for _, c in commits {
        if (stSha != "" && StrLower(c.sha) = stSha)
            break
        if (stDate != "" && c.dateIso != "" && StrCompare(c.dateIso, stDate) <= 0)
            break
        isFirst := (out.Length == 0)
        prefix := isFirst ? "Nightly (Latest)" : "Nightly"
        subjPart := (c.subject != "") ? (" " Chr(0x00B7) " " c.subject) : ""
        lbl := prefix " " Chr(0x2014) " " c.shortSha " (" c.dateShort ")" subjPart
        rawBase := (rawBaseOverride != "")
            ? RTrim(rawBaseOverride, "/")
            : ("https://raw.githubusercontent.com/SaabithJiffry/PresenterSync/" c.sha "/dist")
        out.Push({
            sha: c.sha,
            shortSha: c.shortSha,
            dateIso: c.dateIso,
            dateShort: c.dateShort,
            subject: c.subject,
            url: c.url,
            label: lbl,
            isLatest: isFirst,
            rawBase: rawBase,
            metaUrl: rawBase "/nightly_meta.json",
            sha256Url: rawBase "/SHA256SUMS.txt",
            assetUrl: rawBase "/" assetNm
        })
    }
    return out
}

ResolveNightlyBuildSelection(buildObj, curVer, curSha, assetNm, stableParsed := "", mockFixtures := "") {
    sumsText := ""
    if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("sumsBySha") && mockFixtures.sumsBySha.Has(buildObj.sha)) {
        sumsText := mockFixtures.sumsBySha[buildObj.sha]
    } else if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("nightlySumsText") && mockFixtures.nightlySumsText != "") {
        sumsText := mockFixtures.nightlySumsText
    } else {
        sResp := _FetchHttpTextSimple(buildObj.sha256Url, 12000, "PresenterSync/" curVer)
        if (sResp.ok)
            sumsText := sResp.text
    }
    nightlySha := ParseSha256SumsText(sumsText, assetNm)
    if (nightlySha = "") {
        return {
            ok: false, channel: "Nightly", status: "nightly_unavailable", current: curVer, latest: "",
            updateAvailable: false, isAlreadyInstalled: false, rollbackAvailable: false,
            url: buildObj.url, releaseNotes: "SHA256SUMS.txt missing or does not list " assetNm " on commit " buildObj.shortSha ".",
            assetName: assetNm, assetUrl: buildObj.assetUrl, assetSize: -1, sha256Url: "",
            shortSha: buildObj.shortSha, selectedSha: buildObj.sha,
            statusHeadline: "Nightly SHA256SUMS.txt unavailable on " buildObj.shortSha
        }
    }

    metaText := ""
    if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("metaBySha") && mockFixtures.metaBySha.Has(buildObj.sha)) {
        metaText := mockFixtures.metaBySha[buildObj.sha]
    } else if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("nightlyMetaJson")) {
        metaText := mockFixtures.nightlyMetaJson
    } else {
        mResp := _FetchHttpTextSimple(buildObj.metaUrl, 12000, "PresenterSync/" curVer)
        if (mResp.ok)
            metaText := mResp.text
    }
    meta := (metaText != "") ? ParseNightlyMetaJson(metaText) : { ok: false, version: "", androidVersionCode: 0, builtAtUtc: "" }
    displayVer := meta.ok ? meta.version : (buildObj.shortSha " (" buildObj.dateShort ")")
    verLabel := meta.ok ? ("v" meta.version " @ " buildObj.shortSha) : (buildObj.shortSha " (" buildObj.dateShort ")")

    if (buildObj.isLatest && IsObject(stableParsed) && stableParsed.ok && meta.ok && CompareSemVer(meta.version, stableParsed.version) == 0 && stableParsed.sha256Url != "") {
        stSums := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("stableSumsText"))
            ? mockFixtures.stableSumsText
            : _FetchHttpTextSimple(stableParsed.sha256Url, 12000, "PresenterSync/" curVer).text
        stableSha := ParseSha256SumsText(stSums, assetNm)
        if (stableSha != "" && nightlySha = stableSha) {
            hl := "Nightly has caught up to Stable (v" stableParsed.version ")"
            return {
                ok: true, channel: "Nightly", status: "caught_up_to_stable", current: curVer,
                latest: meta.version, stableVersion: stableParsed.version, shortSha: buildObj.shortSha,
                selectedSha: buildObj.sha, updateAvailable: false, isAlreadyInstalled: true, rollbackAvailable: false,
                url: buildObj.url, releaseNotes: hl, assetName: assetNm, assetUrl: buildObj.assetUrl,
                assetSize: -1, sha256Url: buildObj.sha256Url, statusHeadline: hl
            }
        }
    }

    if (curSha != "" && curSha = nightlySha) {
        hl := "Already Installed (" verLabel ")"
        return {
            ok: true, channel: "Nightly", status: "up_to_date_nightly", current: curVer,
            latest: displayVer, stableVersion: (IsObject(stableParsed) && stableParsed.ok ? stableParsed.version : ""),
            shortSha: buildObj.shortSha, selectedSha: buildObj.sha, updateAvailable: false,
            isAlreadyInstalled: true, rollbackAvailable: false, url: buildObj.url,
            releaseNotes: "Installed executable already matches commit " buildObj.sha " (SHA-256 verified).",
            assetName: assetNm, assetUrl: buildObj.assetUrl, assetSize: -1, sha256Url: buildObj.sha256Url,
            statusHeadline: hl, primaryActionLabel: "Already Installed"
        }
    }

    stSuffix := (IsObject(stableParsed) && stableParsed.ok && stableParsed.version != "") ? (" (Stable: v" stableParsed.version ")") : ""
    hl := (buildObj.isLatest ? "Nightly available: " : "Selected Nightly: ") verLabel stSuffix
    notesN := "Immutable Nightly build pinned to commit " buildObj.sha
        . (buildObj.subject != "" ? "`r`nCommit: " buildObj.subject : "")
        . (meta.ok && meta.builtAtUtc != "" ? "`r`nBuilt UTC: " meta.builtAtUtc : "`r`nDate: " buildObj.dateShort)
        . "`r`n`r`nWarning: Nightly builds come from main (dist/) and are not finalized stable releases."
    return {
        ok: true, channel: "Nightly", status: "nightly_available", current: curVer,
        latest: displayVer, stableVersion: (IsObject(stableParsed) && stableParsed.ok ? stableParsed.version : ""),
        shortSha: buildObj.shortSha, selectedSha: buildObj.sha, updateAvailable: true,
        isAlreadyInstalled: false, rollbackAvailable: false, url: buildObj.url,
        releaseNotes: notesN, assetName: assetNm, assetUrl: buildObj.assetUrl, assetSize: -1,
        sha256Url: buildObj.sha256Url, statusHeadline: hl,
        primaryActionLabel: "Install Selected Nightly (" buildObj.shortSha ")"
    }
}


_QuoteCliArg(val) {
    s := String(val)
    if (s = "")
        return '""'
    return '"' StrReplace(s, '"', '\"') '"'
}

BuildUpdaterRelaunchArgs(args, oldExePath) {
    parts := []
    if (IsObject(args)) {
        i := 1
        while (i <= args.Length) {
            arg := String(args[i])
            low := StrLower(arg)
            if ((low = "--cleanup-old-exe" || low = "-cleanup-old-exe") && i < args.Length) {
                i += 2
                continue
            }
            if RegExMatch(low, "^--?cleanup-old-exe=") {
                i += 1
                continue
            }
            if ((low = "-config" || low = "--config" || low = "-instance" || low = "--instance") && i < args.Length) {
                parts.Push(arg)
                parts.Push(_QuoteCliArg(args[i + 1]))
                i += 2
                continue
            }
            if (RegExMatch(arg, "i)^--?(config|instance)=(.+)$")) {
                parts.Push(_QuoteCliArg(arg))
                i += 1
                continue
            }
            i += 1
        }
    }
    if (oldExePath != "") {
        parts.Push("--cleanup-old-exe")
        parts.Push(_QuoteCliArg(oldExePath))
    }
    joined := ""
    for idx, p in parts
        joined .= (idx > 1 ? " " : "") p
    return joined
}

RegisterSelfUpdateBeforeRelaunch(fn) {
    global g_PresenterSyncBeforeRelaunchFn
    g_PresenterSyncBeforeRelaunchFn := fn
}

PerformAtomicExeSwapAndRelaunch(currentExePath, newExePath, args := "", shouldRelaunch := true, shouldExit := true, beforeRelaunchFn := "") {
    if (!FileExist(currentExePath))
        return { ok: false, reason: "Current executable not found: " currentExePath }
    if (!FileExist(newExePath))
        return { ok: false, reason: "Staged update executable not found: " newExePath }

    oldExePath := currentExePath ".old"
    try FileDelete(oldExePath)
    if (FileExist(oldExePath))
        return { ok: false, reason: "Existing .old backup is locked; retry after closing other instances." }

    movedCurrent := false
    try {
        FileMove(currentExePath, oldExePath, 1)
        movedCurrent := true
        FileMove(newExePath, currentExePath, 1)
    } catch as e {
        if (movedCurrent && !FileExist(currentExePath) && FileExist(oldExePath)) {
            try FileMove(oldExePath, currentExePath, 1)
        }
        return { ok: false, reason: "Atomic executable swap failed: " e.Message }
    }

    if (IsObject(beforeRelaunchFn)) {
        try beforeRelaunchFn.Call()
    } else {
        global g_PresenterSyncBeforeRelaunchFn
        if (IsSet(g_PresenterSyncBeforeRelaunchFn) && IsObject(g_PresenterSyncBeforeRelaunchFn))
            try g_PresenterSyncBeforeRelaunchFn.Call()
    }

    relaunchCmd := _QuoteCliArg(currentExePath)
    argLine := BuildUpdaterRelaunchArgs(IsObject(args) ? args : A_Args, oldExePath)
    if (argLine != "")
        relaunchCmd .= " " argLine

    if (shouldRelaunch) {
        SplitPath(currentExePath, , &exeWorkDir)
        Run(relaunchCmd, exeWorkDir)
    }
    if (shouldExit)
        ExitApp(0)

    return { ok: true, currentExePath: currentExePath, oldExePath: oldExePath, cmd: relaunchCmd, relaunched: shouldRelaunch }
}

ProcessSelfUpdateStartupCleanup(args := "", currentExePath := "") {
    targets := []
    seen := Map()
    AddCleanupTarget(p) {
        cleaned := Trim(String(p), ' "')
        if (cleaned != "" && !seen.Has(StrLower(cleaned))) {
            seen[StrLower(cleaned)] := true
            targets.Push(cleaned)
        }
    }

    argList := IsObject(args) ? args : A_Args
    if (IsObject(argList)) {
        i := 1
        while (i <= argList.Length) {
            arg := String(argList[i])
            low := StrLower(arg)
            if ((low = "--cleanup-old-exe" || low = "-cleanup-old-exe") && i < argList.Length) {
                AddCleanupTarget(argList[i + 1])
                i += 2
                continue
            }
            if (RegExMatch(arg, "i)^--?cleanup-old-exe=(.+)$", &mC)) {
                AddCleanupTarget(mC[1])
            }
            i += 1
        }
    }

    baseExe := (currentExePath != "") ? currentExePath : (A_IsCompiled ? A_ScriptFullPath : "")
    if (baseExe != "")
        AddCleanupTarget(baseExe ".old")

    remaining := []
    for tPath in targets {
        if (FileExist(tPath)) {
            try FileDelete(tPath)
            if (FileExist(tPath))
                remaining.Push(tPath)
        }
    }
    if (remaining.Length == 0)
        return 0

    retries := 0
    retryFn := ""
    _TryCleanRemaining() {
        retries += 1
        nextLeft := []
        for p in remaining {
            if (FileExist(p)) {
                try FileDelete(p)
                if (FileExist(p))
                    nextLeft.Push(p)
            }
        }
        remaining := nextLeft
        if (remaining.Length == 0 || retries >= 15) {
            SetTimer(retryFn, 0)
        }
    }
    retryFn := _TryCleanRemaining
    SetTimer(retryFn, 350)
    return remaining.Length
}

DownloadVerifyAndStageWindowsUpdate(updRes, destPath, onStatus := "", onProgress := "", isCancelledFn := "") {
    if (!IsObject(updRes) || !updRes.HasOwnProp("assetUrl") || updRes.assetUrl = "")
        return { ok: false, cancelled: false, shaVerified: false, reason: "Release asset URL is missing." }

    assetNm := (updRes.HasOwnProp("assetName") && updRes.assetName != "") ? updRes.assetName : GetDefaultWindowsAssetName()
    expectedSha := ""
    if (!updRes.HasOwnProp("sha256Url") || Trim(String(updRes.sha256Url)) = "")
        return { ok: false, cancelled: false, shaVerified: false, reason: "SHA256SUMS.txt URL is missing; refusing unverified update." }
    if (updRes.HasOwnProp("sha256Url") && updRes.sha256Url != "") {
        if (IsObject(onStatus))
            onStatus.Call("Fetching SHA256SUMS.txt...")
        sumsResp := _FetchHttpTextSimple(updRes.sha256Url)
        if (!sumsResp.ok)
            return { ok: false, cancelled: false, shaVerified: false, reason: "Failed to fetch SHA256SUMS.txt (HTTP " sumsResp.status ")." }
        expectedSha := ParseSha256SumsText(sumsResp.text, assetNm)
        if (expectedSha = "")
            return { ok: false, cancelled: false, shaVerified: false, reason: "SHA256SUMS.txt does not list " assetNm "." }
    }

    expectedSize := updRes.HasOwnProp("assetSize") ? updRes.assetSize : -1
    if (IsObject(onStatus))
        onStatus.Call("Downloading v" updRes.latest " (" assetNm ")...")
    dl := StreamHttpToFile(updRes.assetUrl, destPath, expectedSize, onProgress, isCancelledFn)
    if (!dl.ok)
        return { ok: false, cancelled: dl.cancelled, shaVerified: false, reason: dl.reason }

    if (IsObject(onStatus))
        onStatus.Call("Verifying SHA-256 & PE signature...")
    ver := VerifyStagedExecutable(destPath, expectedSize, expectedSha)
    if (!ver.ok)
        return { ok: false, cancelled: false, shaVerified: false, reason: ver.reason }

    return { ok: true, cancelled: false, shaVerified: ver.shaVerified, sha256: ver.sha256, path: destPath, reason: "" }
}

StartWindowsSelfUpdateDownloadUI(updRes, targetExePath := "") {
    curExe := (targetExePath != "") ? targetExePath : A_ScriptFullPath
    if (!A_IsCompiled && targetExePath = "") {
        MsgBox("1-Click In-App Self-Replacement applies to compiled .exe builds.`n`nOpening GitHub Releases so you can inspect v" updRes.latest ".", "Source Script Mode", "Iconi 0x40000")
        try Run(updRes.url)
        return false
    }

    Theme.AcquireSuspend()
    updGui := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Self-Updater")
    updGui.MarginX := 20
    updGui.MarginY := 16
    Theme.ApplyToWindow(updGui)

    cancelled := false
    closed := false
    CleanupDlg(*) {
        if (closed)
            return
        closed := true
        cancelled := true
        Theme.UnregisterWindow(updGui, "SelfUpdaterProgress")
        Theme.ReleaseSuspend()
        try updGui.Destroy()
    }

    updGui.SetFont("s11 w700 norm", Theme.UiFont)
    Theme.RegisterControl(updGui, updGui.Add("Text", "w420", "Updating " updRes.assetName " to v" updRes.latest), "Text")

    updGui.SetFont("s9 w400 norm", Theme.UiFont)
    lblStage := updGui.Add("Text", "w420", "Preparing download...")
    Theme.RegisterControl(updGui, lblStage, "Text", "muted")

    prgBar := updGui.Add("Progress", "w420 h18 Range0-100", 0)
    lblBytes := updGui.Add("Text", "w420", "0.0 MB...")
    Theme.RegisterControl(updGui, lblBytes, "Text", "muted")

    btnCancel := updGui.Add("Button", "x310 y+14 w130 h30", "Cancel")
    Theme.RegisterControl(updGui, btnCancel, "Button")
    btnCancel.OnEvent("Click", (*) => (cancelled := true, btnCancel.Enabled := false, lblStage.Value := "Cancelling download..."))
    updGui.OnEvent("Close", (*) => (cancelled := true))
    updGui.OnEvent("Escape", (*) => (cancelled := true))

    Theme.NamedWindows["SelfUpdaterProgress"] := updGui
    WindowFit.Show(updGui, "w460 Center")
    stageFile := curExe ".update.tmp"
    OnSt(msg) {
        if (!closed)
            lblStage.Value := msg
    }
    OnProg(readBytes, totalBytes, pct) {
        if (!closed) {
            prgBar.Value := pct
            lblBytes.Value := (totalBytes > 0)
                ? Format("{:.1f} MB / {:.1f} MB ({}%)", readBytes / 1048576.0, totalBytes / 1048576.0, pct)
                : Format("{:.1f} MB downloaded...", readBytes / 1048576.0)
        }
    }

    res := DownloadVerifyAndStageWindowsUpdate(updRes, stageFile, OnSt, OnProg, (*) => cancelled)
    if (!res.ok) {
        CleanupDlg()
        if (!res.cancelled)
            MsgBox("Update failed:`n`n" res.reason "`n`nYou can download manually from:`n" updRes.url, "PresenterSync Update Error", "Icon! 0x40000")
        return false
    }

    if (!closed) {
        lblStage.Value := (res.shaVerified ? "✓ SHA-256 verified! " : "✓ PE verified! ") "Replacing executable and restarting..."
        prgBar.Value := 100
    }
    Sleep(250)
    CleanupDlg()

    swap := PerformAtomicExeSwapAndRelaunch(curExe, stageFile, A_Args, true, true)
    if (!swap.ok) {
        try FileDelete(stageFile)
        MsgBox("Could not swap executable:`n`n" swap.reason, "PresenterSync Update Error", "Icon! 0x40000")
        return false
    }
    return true
}

ShowWindowsUpdateAvailableDialog(updRes, cfg := "") {
    existing := Theme.FocusExistingWindow("UpdateAvailablePrompt")
    if IsObject(existing)
        return existing

    Theme.AcquireSuspend()
    dlg := Gui("+AlwaysOnTop -MinimizeBox -MaximizeBox", "PresenterSync Updater")
    dlg.MarginX := 20
    dlg.MarginY := 16
    Theme.ApplyToWindow(dlg)

    CloseDlg(*) {
        Theme.UnregisterWindow(dlg, "UpdateAvailablePrompt")
        Theme.ReleaseSuspend()
        try dlg.Destroy()
    }

    activeRes := updRes
    chan := (activeRes.HasOwnProp("channel") && activeRes.channel != "") ? NormalizeUpdateChannel(activeRes.channel) : "Stable"
    isNightly := (chan = "Nightly")
    isRollback := (activeRes.HasOwnProp("rollbackAvailable") && activeRes.rollbackAvailable)
    headline := (activeRes.HasOwnProp("statusHeadline") && activeRes.statusHeadline != "")
        ? activeRes.statusHeadline
        : ("Update Available: v" activeRes.latest)

    dlg.SetFont("s12 w700 norm", Theme.UiFont)
    lblHeadline := dlg.Add("Text", "w440", headline)
    Theme.RegisterControl(dlg, lblHeadline, "Text")

    dlg.SetFont("s9 w400 norm", Theme.UiFont)
    subLine := "Installed: v" activeRes.current "   |   Channel: " (isNightly ? "Nightly Release" : "Stable Release")
        . (activeRes.sha256Url != "" ? "   |   SHA-256 Protected" : "")
    lblSub := dlg.Add("Text", "w440", subLine)
    Theme.RegisterControl(dlg, lblSub, "Text", "muted")

    Theme.RegisterControl(dlg, dlg.Add("Text", "w96 y+10", "Channel:"), "Text")
    ddlChan := dlg.Add("DropDownList", "x+8 yp-3 w160 Choose" (isNightly ? 2 : 1), ["Stable Release", "Nightly Release"])
    Theme.RegisterControl(dlg, ddlChan, "DropDownList")
    btnRecheck := dlg.Add("Button", "x+8 yp-1 w168 h26", "Refresh Builds")
    Theme.RegisterControl(dlg, btnRecheck, "Button")

    builds := (activeRes.HasOwnProp("nightlyBuilds") && IsObject(activeRes.nightlyBuilds)) ? activeRes.nightlyBuilds : []
    ddlBuilds := ""
    if (isNightly) {
        Theme.RegisterControl(dlg, dlg.Add("Text", "x20 y+10 w96", "Nightly Build:"), "Text")
        buildItems := []
        for _, b in builds
            buildItems.Push(b.label)
        if (buildItems.Length == 0)
            buildItems.Push("Nightly has caught up to Stable")
        ddlBuilds := dlg.Add("DropDownList", "x+8 yp-3 w336 Choose1" (builds.Length == 0 ? " Disabled" : ""), buildItems)
        Theme.RegisterControl(dlg, ddlBuilds, "DropDownList")
    }

    lblNightlyWarn := dlg.Add("Text", "x20 y+8 w440" (isNightly ? "" : " Hidden"), "Warning: Nightly builds come from main commits (dist/), are not finalized stable releases, and some features may be incomplete or unstable.")
    lblNightlyWarn.SetFont("s8.5 w600 norm", Theme.UiFont)
    lblNightlyWarn.Opt("cF59E0B")
    ddlChan.OnEvent("Change", (*) => (
        lblNightlyWarn.Visible := (ddlChan.Value == 2),
        IsObject(cfg) ? (cfg.UpdateChannel := (ddlChan.Value == 2 ? "Nightly" : "Stable"), cfg.Write("Settings", "UpdateChannel", cfg.UpdateChannel)) : 0
    ))

    notes := (activeRes.HasOwnProp("releaseNotes") && activeRes.releaseNotes != "") ? activeRes.releaseNotes : "Signed release update from SaabithJiffry/PresenterSync."
    edNotes := dlg.Add("Edit", "x20 y+8 w440 h122 ReadOnly Multi VScroll", StrReplace(notes, "`n", "`r`n"))
    Theme.RegisterControl(dlg, edNotes, "Edit")

    canSelfInstall := (activeRes.HasOwnProp("assetUrl") && activeRes.assetUrl != "" && A_IsCompiled && (activeRes.updateAvailable || isRollback))
    alreadyInst := (activeRes.HasOwnProp("isAlreadyInstalled") && activeRes.isAlreadyInstalled)
    primaryLabel := (activeRes.HasOwnProp("primaryActionLabel") && activeRes.primaryActionLabel != "")
        ? activeRes.primaryActionLabel
        : (isRollback ? ("Roll back to Stable v" activeRes.latest) : "Download && Install Now")
    btnPrimary := dlg.Add("Button", "x20 y+14 w214 h34 Default" (alreadyInst ? " Disabled" : ""), canSelfInstall ? primaryLabel : (alreadyInst ? "Already Installed" : "Open Release Page"))
    Theme.RegisterControl(dlg, btnPrimary, "Button", "accent")
    btnBrowser := dlg.Add("Button", "x246 yp w214 h34", "Open in Browser")
    Theme.RegisterControl(dlg, btnBrowser, "Button")

    btnSkip := dlg.Add("Button", "x20 y+8 w214 h30" ((isRollback || isNightly) ? " Disabled" : ""), "Skip v" activeRes.latest)
    Theme.RegisterControl(dlg, btnSkip, "Button")
    btnLater := dlg.Add("Button", "x246 yp w214 h30", "Later")
    Theme.RegisterControl(dlg, btnLater, "Button")

    if (IsObject(ddlBuilds) && builds.Length > 0) {
        _OnNightlyBuildPicked(*) {
            idx := ddlBuilds.Value
            if (idx < 1 || idx > builds.Length)
                return
            selB := builds[idx]
            curSha := GetCurrentBinarySha256()
            assetNm := (activeRes.HasOwnProp("assetName") && activeRes.assetName != "") ? activeRes.assetName : GetDefaultWindowsAssetName()
            resolved := ResolveNightlyBuildSelection(selB, activeRes.current, curSha, assetNm)
            resolved.nightlyBuilds := builds
            activeRes := resolved
            lblHeadline.Value := resolved.statusHeadline
            edNotes.Value := StrReplace(resolved.releaseNotes, "`n", "`r`n")
            canNow := (resolved.assetUrl != "" && A_IsCompiled && resolved.updateAvailable)
            btnPrimary.Enabled := !(resolved.HasOwnProp("isAlreadyInstalled") && resolved.isAlreadyInstalled)
            btnPrimary.Text := canNow ? resolved.primaryActionLabel : ((resolved.HasOwnProp("isAlreadyInstalled") && resolved.isAlreadyInstalled) ? "Already Installed" : "Open Commit Page")
        }
        ddlBuilds.OnEvent("Change", _OnNightlyBuildPicked)
    }

    OnRecheckClick(*) {
        newChan := (ddlChan.Value == 2) ? "Nightly" : "Stable"
        if IsObject(cfg) {
            cfg.UpdateChannel := newChan
            try cfg.Write("Settings", "UpdateChannel", newChan)
        }
        assetNm := (activeRes.HasOwnProp("assetName") && activeRes.assetName != "") ? activeRes.assetName : GetDefaultWindowsAssetName()
        curVer := activeRes.current
        CloseDlg()
        CheckForUpdates(curVer, "", false, assetNm, cfg, newChan)
    }

    OnPrimaryClick(*) {
        resSnap := activeRes
        canInstNow := (resSnap.HasOwnProp("assetUrl") && resSnap.assetUrl != "" && A_IsCompiled && (resSnap.updateAvailable || (resSnap.HasOwnProp("rollbackAvailable") && resSnap.rollbackAvailable)))
        CloseDlg()
        if (canInstNow) {
            StartWindowsSelfUpdateDownloadUI(resSnap)
        } else {
            try Run(resSnap.url)
        }
    }
    OnBrowserClick(*) {
        try Run(activeRes.url)
        CloseDlg()
    }
    OnSkipClick(*) {
        if IsObject(cfg) {
            cfg.SkippedUpdateVersion := activeRes.latest
            try cfg.Write("Settings", "SkippedUpdateVersion", activeRes.latest)
        }
        CloseDlg()
    }

    btnRecheck.OnEvent("Click", OnRecheckClick)
    btnPrimary.OnEvent("Click", OnPrimaryClick)
    btnBrowser.OnEvent("Click", OnBrowserClick)
    btnSkip.OnEvent("Click", OnSkipClick)
    btnLater.OnEvent("Click", CloseDlg)
    dlg.OnEvent("Close", CloseDlg)
    dlg.OnEvent("Escape", CloseDlg)

    Theme.NamedWindows["UpdateAvailablePrompt"] := dlg
    WindowFit.Show(dlg, "w480 AutoSize Center")
    btnPrimary.Focus()
    return dlg
}

CheckForUpdates(currentVer := "", mockResponseJson := "", silent := true, targetAssetName := "", cfg := "", overrideChannel := "", mockFixtures := "") {
    cur := (currentVer != "") ? RegExReplace(Trim(String(currentVer)), "^[vV]") : UIConstants.APP_VERSION
    assetNm := (targetAssetName != "") ? targetAssetName : GetDefaultWindowsAssetName()
    fallbackUrl := "https://github.com/SaabithJiffry/PresenterSync/releases"
    channel := (overrideChannel != "")
        ? NormalizeUpdateChannel(overrideChannel)
        : ((IsObject(cfg) && cfg.HasOwnProp("UpdateChannel")) ? NormalizeUpdateChannel(cfg.UpdateChannel) : "Stable")
    curExePath := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("currentExePath")) ? mockFixtures.currentExePath : ""
    curSha := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("currentBinarySha256"))
        ? StrLower(Trim(String(mockFixtures.currentBinarySha256)))
        : GetCurrentBinarySha256(curExePath)

    if (channel = "Nightly") {
        ; 1. Resolve latest Stable tag + its commit SHA/date
        stJson := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("stableReleaseJson")) ? mockFixtures.stableReleaseJson : ""
        if (stJson = "") {
            stResp := _FetchHttpTextSimple("https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest", 12000, "PresenterSync/" cur, "application/vnd.github+json")
            if (stResp.status == 403 || stResp.status == 429) {
                if (!silent)
                    MsgBox("GitHub API rate limit reached (HTTP " stResp.status "). Please try again later.", "Nightly Update Check", "Icon! 0x40000")
                return { ok: false, channel: "Nightly", status: "rate_limited", current: cur, latest: "", updateAvailable: false, url: fallbackUrl, releaseNotes: "", assetName: assetNm, assetUrl: "", assetSize: -1, sha256Url: "", nightlyBuilds: [], statusHeadline: "GitHub API rate limit reached (HTTP " stResp.status ")" }
            }
            if (stResp.ok)
                stJson := stResp.text
        }
        stableParsed := (stJson != "") ? ParseGitHubReleaseDetails(stJson, assetNm) : { ok: false, tag: "", version: "", sha256Url: "", url: fallbackUrl }

        stableCommitSha := ""
        stableCommitDate := ""
        if (stableParsed.ok && stableParsed.tag != "") {
            scJson := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("stableCommitJson")) ? mockFixtures.stableCommitJson : ""
            if (scJson = "") {
                scResp := _FetchHttpTextSimple("https://api.github.com/repos/SaabithJiffry/PresenterSync/commits/" stableParsed.tag, 12000, "PresenterSync/" cur, "application/vnd.github+json")
                if (scResp.ok)
                    scJson := scResp.text
            }
            if (scJson != "") {
                scInfo := ParseGitHubCommitDetails(scJson)
                if (scInfo.ok) {
                    stableCommitSha := scInfo.sha
                    stableCommitDate := scInfo.date
                }
            }
        }

        ; 2. Fetch commits touching dist/<TargetBinary> in a single API call
        listJson := ""
        listStatus := 200
        if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("commitListJson")) {
            listJson := mockFixtures.commitListJson
        } else {
            lUrl := "https://api.github.com/repos/SaabithJiffry/PresenterSync/commits?sha=main&path=dist/" assetNm "&per_page=20"
            lResp := _FetchHttpTextSimple(lUrl, 12000, "PresenterSync/" cur, "application/vnd.github+json")
            listStatus := lResp.status
            if (lResp.ok)
                listJson := lResp.text
        }
        if (listStatus == 403 || listStatus == 429) {
            if (!silent)
                MsgBox("GitHub API rate limit reached (HTTP " listStatus "). Please try again later.", "Nightly Update Check", "Icon! 0x40000")
            return { ok: false, channel: "Nightly", status: "rate_limited", current: cur, latest: "", updateAvailable: false, url: fallbackUrl, releaseNotes: "", assetName: assetNm, assetUrl: "", assetSize: -1, sha256Url: "", nightlyBuilds: [], statusHeadline: "GitHub API rate limit reached (HTTP " listStatus ")" }
        }
        if (listJson = "") {
            if (!silent)
                MsgBox("Unable to query Nightly builds from GitHub.`n`nReleases: " fallbackUrl, "Nightly Update Check", "Icon! 0x40000")
            return { ok: false, channel: "Nightly", status: "error", current: cur, latest: "", updateAvailable: false, url: fallbackUrl, releaseNotes: "", assetName: assetNm, assetUrl: "", assetSize: -1, sha256Url: "", nightlyBuilds: [], statusHeadline: "Could not query Nightly commits" }
        }

        rawBaseOv := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("rawBaseUrl")) ? mockFixtures.rawBaseUrl : ""
        allCommits := ParseGitHubCommitListJson(listJson)
        builds := FilterPostStableNightlyCommits(allCommits, stableCommitSha, stableCommitDate, rawBaseOv, assetNm)

        if (IsObject(cfg)) {
            cfg.LastUpdateCheckEpoch := GetCurrentUnixEpoch()
            try cfg.Write("Settings", "LastUpdateCheckEpoch", cfg.LastUpdateCheckEpoch)
        }

        if (builds.Length == 0) {
            stVer := (stableParsed.ok && stableParsed.version != "") ? stableParsed.version : cur
            hl := "Nightly has caught up to Stable (v" stVer ")"
            resCaught := {
                ok: true, channel: "Nightly", status: "caught_up_to_stable", current: cur,
                latest: stVer, stableVersion: stVer, updateAvailable: false, isAlreadyInstalled: true,
                rollbackAvailable: false, url: stableParsed.url, releaseNotes: hl "`r`n`r`nNo commits touch dist/" assetNm " after Stable v" stVer ".",
                assetName: assetNm, assetUrl: "", assetSize: -1, sha256Url: "",
                nightlyBuilds: [], statusHeadline: hl, primaryActionLabel: "Already Installed"
            }
            if (!silent)
                ShowWindowsUpdateAvailableDialog(resCaught, cfg)
            return resCaught
        }

        selIdx := 1
        if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("selectedBuildIndex") && Integer(mockFixtures.selectedBuildIndex) >= 1 && Integer(mockFixtures.selectedBuildIndex) <= builds.Length)
            selIdx := Integer(mockFixtures.selectedBuildIndex)
        resolved := ResolveNightlyBuildSelection(builds[selIdx], cur, curSha, assetNm, stableParsed, mockFixtures)
        resolved.nightlyBuilds := builds
        if (!silent)
            ShowWindowsUpdateAvailableDialog(resolved, cfg)
        return resolved
    }

    rawJson := ""
    httpOk := false
    lastHttpStatus := 0

    if (mockResponseJson != "") {
        rawJson := mockResponseJson
        httpOk := true
    } else if (IsObject(mockFixtures) && mockFixtures.HasOwnProp("stableReleaseJson") && mockFixtures.stableReleaseJson != "") {
        rawJson := mockFixtures.stableReleaseJson
        httpOk := true
    } else {
        for apiUrl in [
            "https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest",
            "https://api.github.com/repos/SaabithJiffry/PresenterSync/tags"
        ] {
            r := _FetchHttpTextSimple(apiUrl, 12000, "PresenterSync/" cur, "application/vnd.github+json")
            lastHttpStatus := r.status
            if (r.ok) {
                rawJson := r.text
                httpOk := true
                break
            }
            if (r.status == 403 || r.status == 429)
                break
        }
    }

    if (lastHttpStatus == 403 || lastHttpStatus == 429) {
        if (!silent)
            MsgBox("GitHub API rate limit reached (HTTP " lastHttpStatus "). Please try again later.`n`nReleases page: " fallbackUrl, "Update Check", "Icon! 0x40000")
        return { ok: false, channel: "Stable", status: "rate_limited", current: cur, latest: "", updateAvailable: false, url: fallbackUrl, releaseNotes: "", assetName: assetNm, assetUrl: "", assetSize: -1, sha256Url: "", statusHeadline: "GitHub API rate limit reached (HTTP " lastHttpStatus ")" }
    }

    parsed := httpOk ? ParseGitHubReleaseDetails(rawJson, assetNm) : { ok: false, tag: "", version: "", url: "", releaseNotes: "", assetName: "", assetUrl: "", assetSize: -1, sha256Url: "" }
    if (!parsed.ok) {
        if (!silent)
            MsgBox("Unable to check GitHub for updates right now (offline or rate-limited).`n`nReleases page: " fallbackUrl, "Update Check", "Icon! 0x40000")
        return { ok: false, channel: "Stable", status: "error", current: cur, latest: "", updateAvailable: false, url: fallbackUrl, releaseNotes: "", assetName: "", assetUrl: "", assetSize: -1, sha256Url: "", statusHeadline: "Unable to check GitHub for updates" }
    }

    if (IsObject(cfg)) {
        cfg.LastUpdateCheckEpoch := GetCurrentUnixEpoch()
        try cfg.Write("Settings", "LastUpdateCheckEpoch", cfg.LastUpdateCheckEpoch)
    }

    relUrl := (parsed.url != "") ? parsed.url : fallbackUrl
    cmp := CompareSemVer(parsed.version, cur)
    if (cmp > 0) {
        resObj := {
            ok: true, channel: "Stable", status: "update_available", current: cur,
            latest: parsed.version, updateAvailable: true, rollbackAvailable: false,
            url: relUrl, releaseNotes: parsed.releaseNotes, assetName: parsed.assetName,
            assetUrl: parsed.assetUrl, assetSize: parsed.assetSize, sha256Url: parsed.sha256Url,
            statusHeadline: "Stable update available: v" parsed.version,
            primaryActionLabel: "Download && Install Now"
        }
        if (!silent)
            ShowWindowsUpdateAvailableDialog(resObj, cfg)
        return resObj
    }

    if (cmp == 0 && curSha != "" && parsed.sha256Url != "") {
        stSums := (IsObject(mockFixtures) && mockFixtures.HasOwnProp("stableSumsText"))
            ? mockFixtures.stableSumsText
            : _FetchHttpTextSimple(parsed.sha256Url, 12000, "PresenterSync/" cur).text
        stableSha := ParseSha256SumsText(stSums, parsed.assetName != "" ? parsed.assetName : assetNm)
        if (stableSha != "" && stableSha != curSha) {
            resHandoff := {
                ok: true, channel: "Stable", status: "stable_handoff", current: cur,
                latest: parsed.version, updateAvailable: true, rollbackAvailable: false,
                url: relUrl, releaseNotes: parsed.releaseNotes, assetName: parsed.assetName,
                assetUrl: parsed.assetUrl, assetSize: parsed.assetSize, sha256Url: parsed.sha256Url,
                statusHeadline: "Install Stable v" parsed.version " (replaces Nightly build)",
                primaryActionLabel: "Install Stable v" parsed.version
            }
            if (!silent)
                ShowWindowsUpdateAvailableDialog(resHandoff, cfg)
            return resHandoff
        }
    }

    if (cmp < 0) {
        canRb := (parsed.assetUrl != "" && parsed.sha256Url != "")
        hl := "Running Nightly v" cur " (ahead of Stable v" parsed.version ")"
        resAhead := {
            ok: true, channel: "Stable", status: "ahead_of_stable", current: cur,
            latest: parsed.version, updateAvailable: false, rollbackAvailable: canRb,
            url: relUrl,
            releaseNotes: "You are currently running v" cur ", which is newer than the latest Stable Release (v" parsed.version ").`r`n`r`nYou can continue running this build or optionally roll back to Stable v" parsed.version ".",
            assetName: parsed.assetName, assetUrl: parsed.assetUrl, assetSize: parsed.assetSize,
            sha256Url: parsed.sha256Url, statusHeadline: hl,
            primaryActionLabel: "Roll back to Stable v" parsed.version
        }
        if (!silent)
            ShowWindowsUpdateAvailableDialog(resAhead, cfg)
        return resAhead
    }

    if (!silent)
        MsgBox("You are running the latest Stable release of PresenterSync (v" cur ").", "Up to Date", "Iconi 0x40000")
    return {
        ok: true, channel: "Stable", status: "up_to_date", current: cur,
        latest: parsed.version, updateAvailable: false, rollbackAvailable: false,
        url: relUrl, releaseNotes: parsed.releaseNotes, assetName: parsed.assetName,
        assetUrl: parsed.assetUrl, assetSize: parsed.assetSize, sha256Url: parsed.sha256Url,
        statusHeadline: "Up to date on Stable (v" cur ")"
    }
}

StartBackgroundUpdateChecker(cfg, targetAssetName := "", intervalSeconds := 86400) {
    if (!IsObject(cfg) || !cfg.HasOwnProp("AutoCheckUpdates") || !cfg.AutoCheckUpdates)
        return false
    nowEp := GetCurrentUnixEpoch()
    lastEp := cfg.HasOwnProp("LastUpdateCheckEpoch") ? Integer(cfg.LastUpdateCheckEpoch) : 0
    if ((nowEp - lastEp) < intervalSeconds)
        return false

    _RunBgUpdateCheck() {
        if (!cfg.AutoCheckUpdates)
            return
        url := "https://api.github.com/repos/SaabithJiffry/PresenterSync/releases/latest"
        req := ""
        try {
            req := ComObject("WinHttp.WinHttpRequest.5.1")
            req.Open("GET", url, true)
            req.SetRequestHeader("Accept", "application/vnd.github+json")
            req.SetRequestHeader("User-Agent", "PresenterSync/" UIConstants.APP_VERSION)
            req.Send()
        } catch {
            return
        }
        startTick := A_TickCount
        pollFn := ""
        _PollAsyncUpdate() {
            if (!IsObject(req)) {
                if (IsObject(pollFn))
                    try SetTimer(pollFn, 0)
                return
            }
            done := false
            try done := !!req.WaitForResponse(0)
            catch {
                if (IsObject(pollFn))
                    try SetTimer(pollFn, 0)
                req := ""
                return
            }
            if (!done) {
                if ((A_TickCount - startTick) >= 8000) {
                    if (IsObject(pollFn))
                        try SetTimer(pollFn, 0)
                    try req.Abort()
                    req := ""
                }
                return
            }
            if (IsObject(pollFn))
                try SetTimer(pollFn, 0)
            try {
                if (Integer(req.Status) == 200) {
                    body := String(req.ResponseText)
                    try cfg.Write("Settings", "LastUpdateCheckEpoch", String(GetCurrentUnixEpoch()))
                    parsed := ParseGitHubReleaseDetails(body, targetAssetName)
                    cur := LTrim(String(UIConstants.APP_VERSION), "vV")
                    if (parsed.ok && CompareSemVer(parsed.version, cur) > 0) {
                        skipped := cfg.HasOwnProp("SkippedUpdateVersion") ? cfg.SkippedUpdateVersion : ""
                        if (parsed.version != skipped)
                            TrayTip("PresenterSync v" parsed.version " is available! Open Tray -> Check for Updates... to 1-click install.", "PresenterSync Update Ready", 1)
                    }
                }
            } finally {
                req := ""
            }
        }
        pollFn := _PollAsyncUpdate
        SetTimer(pollFn, 150)
    }
    SetTimer(_RunBgUpdateCheck, -8000)
    return true
}

CheckForUpdatesUI(currentVer := "", *) => CheckForUpdates(currentVer, "", false)

