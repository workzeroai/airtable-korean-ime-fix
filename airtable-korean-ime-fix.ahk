; =============================================================================
; airtable-korean-ime-fix.ahk
; 에어테이블 셀을 선택한 상태에서 바로 한글을 치면 첫 글자가 영문으로 들어가는 문제를 줄인다.
;
; 원리: 셀이 "선택만 된" 상태에서 글자 키가 눌리면, 편집 모드 진입 키(F2)를 먼저 보내
;       편집 칸을 연 뒤 원래 키를 다시 보낸다. 이미 편집 중이면 아무것도 하지 않는다.
;
; 버전: 1.0.0 · 라이선스: MIT · AutoHotkey v2 전용
; =============================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force

; ---------------------------------------------------------------- 설정
APP_NAME := "airtable-korean-ime-fix"
APP_VERSION := "1.0.0"

; 브라우저: 활성 탭 제목(= 창 제목)에 TITLE_KEYWORD가 들어 있을 때만 동작
BROWSER_EXES := ["chrome.exe", "msedge.exe"]
TITLE_KEYWORD := "Airtable"

; 데스크톱 앱: 창 제목과 관계없이 동작 (실행 파일 이름이 다르면 여기에 추가)
DESKTOP_APP_EXES := ["Airtable.exe"]

; F2를 보낸 뒤 편집 칸이 열릴 때까지 기다리는 시간(ms). 첫 글자가 여전히 새면 60~100으로 늘린다
F2_DELAY_MS := 40

; true면 한글 입력 상태일 때만 개입한다(영문 상태에서는 원래 동작 그대로)
ONLY_WHEN_HANGUL := true

; 실행 직후 켜진 상태로 시작할지
START_ENABLED := true

; 켜기/끄기 단축키. 빈 값이면 쓰지 않는다. 예: "^!h" = Ctrl+Alt+H
TOGGLE_HOTKEY := ""

; 트레이 메뉴 항목 이름
MENU_ENABLED := "한글 입력 보정 사용"
MENU_STARTUP := "Windows 시작 시 자동 실행"

; ---------------------------------------------------------------- 상태
; editing: 지금 셀이 편집 모드인지에 대한 "추정"값.
;   이 스크립트는 화면(웹 페이지 내부)을 읽지 못한다. 그래서 사용자가 누른 키와 클릭으로
;   상태를 추정한다. 규칙은 아래와 같다.
;     - 우리가 F2+글자를 보낸 뒤, 사용자가 F2를 누른 뒤, 더블클릭한 뒤  → 편집 중
;     - Esc, Tab, 한 번 클릭, 다른 창·탭으로 이동                       → 선택 상태
;     - Enter                                                          → 상태 뒤집기
;       (선택 상태에서 Enter는 편집 시작, 편집 중 Enter는 확정)
;   한계: 화면 상태와 추정이 어긋나는 경우가 있다(README "알려진 한계" 참고).
;         어긋나면 Esc를 한 번 누르면 "선택 상태"로 다시 맞춰진다.
State := {enabled: START_ENABLED, editing: false, lastWindow: ""}

; ---------------------------------------------------------------- 시작
SetupTray()

if (TOGGLE_HOTKEY != "")
    Hotkey(TOGGLE_HOTKEY, ToggleEnabled)

; 글자 키 A~Z(가상 키 코드 vk41~vk5A)를 Shift 유무별로 등록한다.
; 한글 자모는 이 키들로만 입력되므로 숫자·기호·스페이스는 건드리지 않는다.
; Ctrl·Alt·Win이 함께 눌린 조합(단축키)은 이 핫키에 걸리지 않아 그대로 통과한다.
HotIf(ShouldIntercept)
Loop 26 {
    vk := Format("vk{:X}", 0x40 + A_Index)
    Hotkey("$" vk, OnLetterKey)
    Hotkey("$+" vk, OnLetterKey)
}
HotIf()

; ---------------------------------------------------------------- 상태를 바꾸는 키(가로채지 않고 관찰만: ~)
#HotIf State.enabled && IsTargetWindow()
~Esc::State.editing := false
~Tab::State.editing := false
~+Tab::State.editing := false
~Enter::State.editing := !State.editing
~NumpadEnter::State.editing := !State.editing
~F2::State.editing := true
~LButton::OnClick()
#HotIf

; ---------------------------------------------------------------- 핵심 처리

; 글자 키를 가로챌지 결정한다: 켜져 있고, 대상 창이고, 편집 중이 아닐 때만.
ShouldIntercept(*) {
    return State.enabled && !State.editing && IsTargetWindow()
}

; 셀 선택 상태에서 글자 키가 눌렸을 때: F2 → 잠깐 대기 → 원래 키.
OnLetterKey(hotkeyName) {
    ; 처리 중에 빠르게 이어 친 키는 이 처리가 끝날 때까지 대기열에 쌓여 순서가 지켜진다
    Critical
    key := "{Blind}{" RegExReplace(hotkeyName, "^[$+]+") "}"   ; 예: {Blind}{vk41}, Shift는 그대로 유지

    ; 이미 편집 중으로 바뀌었거나(대기열에 있던 키), 한글 상태가 아니면 원래 키만 보낸다
    if (State.editing || (ONLY_WHEN_HANGUL && !IsHangulMode())) {
        SendInput(key)
        return
    }

    SendInput("{F2}")      ; 편집 모드 진입(Shift가 눌려 있어도 F2만 단독으로 보낸다)
    Sleep(F2_DELAY_MS)     ; 편집 칸이 열리고 입력 커서가 들어갈 시간
    SendInput(key)         ; 원래 키 → IME가 한글 조합을 시작한다
    State.editing := true  ; 이후 키는 가로채지 않는다
}

; 한 번 클릭은 셀 선택, 더블클릭은 편집 시작으로 본다.
OnClick() {
    isDouble := (A_PriorHotkey = A_ThisHotkey)
        && (A_TimeSincePriorHotkey < DllCall("GetDoubleClickTime"))
    State.editing := isDouble
}

; ---------------------------------------------------------------- 판별 함수

; 활성 창이 에어테이블(브라우저 탭 또는 데스크톱 앱)인지 확인한다.
; 창이나 탭(제목)이 바뀌면 편집 상태 추정을 "선택 상태"로 초기화한다.
IsTargetWindow() {
    try {
        hwnd := WinExist("A")
        if !hwnd
            return false
        exe := WinGetProcessName(hwnd)
        title := WinGetTitle(hwnd)
    } catch {
        return false
    }

    if ListHas(DESKTOP_APP_EXES, exe)
        ok := true
    else if ListHas(BROWSER_EXES, exe)
        ok := InStr(title, TITLE_KEYWORD) > 0
    else
        ok := false

    windowKey := hwnd "|" title
    if (ok && windowKey != State.lastWindow) {
        State.lastWindow := windowKey
        State.editing := false
    }
    return ok
}

; 현재 입력기가 한글 상태인지 확인한다(Windows IME 변환 모드의 "한글" 비트).
; 확인할 수 없으면 true를 돌려 개입한다(증상 해결 쪽을 우선).
IsHangulMode() {
    hwnd := WinExist("A")
    try {
        focused := ControlGetFocus("A")
        if focused
            hwnd := focused
    }
    imeWnd := DllCall("imm32\ImmGetDefaultIMEWnd", "Ptr", hwnd, "Ptr")
    if !imeWnd
        return true

    prevHidden := DetectHiddenWindows(true)   ; IME 창은 숨겨진 창이다
    try {
        ; WM_IME_CONTROL(0x283) + IMC_GETCONVERSIONMODE(0x1) → 변환 모드 비트값
        mode := SendMessage(0x283, 0x1, 0, , "ahk_id " imeWnd, , , , 200)
    } catch {
        mode := 1
    }
    DetectHiddenWindows(prevHidden)
    return (mode & 1) != 0   ; IME_CMODE_NATIVE(1) = 한글 입력 상태
}

ListHas(list, value) {
    for item in list
        if (StrLower(item) = StrLower(value))
            return true
    return false
}

; ---------------------------------------------------------------- 트레이 메뉴
SetupTray() {
    tray := A_TrayMenu
    tray.Delete()                       ; AutoHotkey 기본 메뉴를 지우고 필요한 것만 둔다
    tray.Add(MENU_ENABLED, ToggleEnabled)
    tray.Add(MENU_STARTUP, ToggleStartup)
    tray.Add()
    tray.Add("종료", (*) => ExitApp())
    tray.Default := MENU_ENABLED        ; 트레이 아이콘 더블클릭 = 켜기/끄기
    RefreshTray()
}

RefreshTray() {
    tray := A_TrayMenu
    if State.enabled
        tray.Check(MENU_ENABLED)
    else
        tray.Uncheck(MENU_ENABLED)
    if FileExist(StartupLinkPath())
        tray.Check(MENU_STARTUP)
    else
        tray.Uncheck(MENU_STARTUP)
    A_IconTip := APP_NAME " " APP_VERSION (State.enabled ? " · 켜짐" : " · 꺼짐")
}

ToggleEnabled(*) {
    State.enabled := !State.enabled
    State.editing := false
    RefreshTray()
    TrayTip(State.enabled ? "한글 입력 보정을 켰습니다." : "한글 입력 보정을 껐습니다.", APP_NAME)
}

; 시작 프로그램 폴더에 바로가기를 만들거나 지운다(관리자 권한 불필요).
StartupLinkPath() => A_Startup "\" APP_NAME ".lnk"

ToggleStartup(*) {
    link := StartupLinkPath()
    try {
        if FileExist(link) {
            FileDelete(link)
        } else if A_IsCompiled {
            FileCreateShortcut(A_ScriptFullPath, link, A_ScriptDir, , APP_NAME)
        } else {
            FileCreateShortcut(A_AhkPath, link, A_ScriptDir, '"' A_ScriptFullPath '"', APP_NAME)
        }
    } catch as err {
        MsgBox("시작 프로그램 설정을 바꾸지 못했습니다.`n" err.Message, APP_NAME, "Icon!")
    }
    RefreshTray()
}
