// Configuration dialog and persistence for x64dbg-MCP Server.
// Uses raw Win32 API to create a modal config dialog.

const std = @import("std");
const bridge = @import("bridge.zig");
const mcp = @import("mcp_server.zig");

// ── Win32 types ────────────────────────────────────────────────────
const HWND = ?*anyopaque;
const HMENU = ?*anyopaque;
const HINSTANCE = ?*anyopaque;
const HFONT = ?*anyopaque;
const HBRUSH = ?*anyopaque;
const HICON = ?*anyopaque;
const HCURSOR = ?*anyopaque;
const HDC = ?*anyopaque;
const HANDLE = ?*anyopaque;
const WPARAM = usize;
const LPARAM = isize;
const LRESULT = isize;
const BOOL = i32;
const RECT = extern struct { left: i32, top: i32, right: i32, bottom: i32 };

const WNDCLASSEXA = extern struct {
    cbSize: u32 = @sizeOf(WNDCLASSEXA),
    style: u32 = 0,
    lpfnWndProc: *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT,
    cbClsExtra: c_int = 0,
    cbWndExtra: c_int = 0,
    hInstance: HINSTANCE = null,
    hIcon: HICON = null,
    hCursor: HCURSOR = null,
    hbrBackground: HBRUSH = null,
    lpszMenuName: ?[*:0]const u8 = null,
    lpszClassName: [*:0]const u8,
    hIconSm: HICON = null,
};

// ── Win32 imports ──────────────────────────────────────────────────
extern "user32" fn RegisterClassExA(lpWndClass: *const WNDCLASSEXA) callconv(.winapi) u16;
extern "user32" fn CreateWindowExA(dwExStyle: u32, lpClassName: [*:0]const u8, lpWindowName: ?[*:0]const u8, dwStyle: u32, x: c_int, y: c_int, nWidth: c_int, nHeight: c_int, hWndParent: HWND, hMenu: HMENU, hInstance: HINSTANCE, lpParam: ?*anyopaque) callconv(.winapi) HWND;
extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn ShowWindow(hWnd: HWND, nCmdShow: c_int) callconv(.winapi) BOOL;
extern "user32" fn UpdateWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn GetMessageA(lpMsg: *MSG, hWnd: HWND, wMsgFilterMin: u32, wMsgFilterMax: u32) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageA(lpMsg: *const MSG) callconv(.winapi) LRESULT;
extern "user32" fn PostQuitMessage(nExitCode: c_int) callconv(.winapi) void;
extern "user32" fn SendMessageA(hWnd: HWND, msg: u32, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn GetWindowTextA(hWnd: HWND, lpString: [*]u8, nMaxCount: c_int) callconv(.winapi) c_int;
extern "user32" fn SetFocus(hWnd: HWND) callconv(.winapi) HWND;
extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
extern "user32" fn EnableWindow(hWnd: HWND, bEnable: BOOL) callconv(.winapi) BOOL;
extern "user32" fn IsDialogMessageA(hDlg: HWND, lpMsg: *MSG) callconv(.winapi) BOOL;
extern "user32" fn GetSystemMetrics(nIndex: c_int) callconv(.winapi) c_int;
extern "user32" fn SetWindowPos(hWnd: HWND, hWndInsertAfter: HWND, x: c_int, y: c_int, cx: c_int, cy: c_int, uFlags: u32) callconv(.winapi) BOOL;
extern "user32" fn MessageBoxA(hWnd: HWND, lpText: [*:0]const u8, lpCaption: [*:0]const u8, uType: u32) callconv(.winapi) c_int;
extern "gdi32" fn CreateFontA(cHeight: c_int, cWidth: c_int, cEscapement: c_int, cOrientation: c_int, cWeight: c_int, bItalic: u32, bUnderline: u32, bStrikeOut: u32, iCharSet: u32, iOutPrecision: u32, iClipPrecision: u32, iQuality: u32, iPitchAndFamily: u32, pszFaceName: [*:0]const u8) callconv(.winapi) HFONT;
extern "gdi32" fn DeleteObject(ho: ?*anyopaque) callconv(.winapi) BOOL;
extern "user32" fn DefWindowProcA(hWnd: HWND, msg: u32, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT;
extern "user32" fn OpenClipboard(hWndNewOwner: HWND) callconv(.winapi) BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
extern "user32" fn SetClipboardData(uFormat: u32, hMem: HANDLE) callconv(.winapi) HANDLE;
extern "gdi32" fn GetStockObject(i: c_int) callconv(.winapi) ?*anyopaque;
extern "gdi32" fn SetBkColor(hdc: HDC, color: u32) callconv(.winapi) u32;

extern "kernel32" fn GetModuleHandleA(lpModuleName: ?[*:0]const u8) callconv(.winapi) HINSTANCE;
extern "kernel32" fn CreateFileA(name: [*:0]const u8, access: u32, share: u32, sa: ?*anyopaque, disp: u32, flags: u32, template: ?*anyopaque) callconv(.winapi) HANDLE;
extern "kernel32" fn ReadFile(h: ?*anyopaque, buf: [*]u8, len: u32, read: *u32, ov: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn WriteFile(h: ?*anyopaque, buf: [*]const u8, len: u32, written: *u32, ov: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn CloseHandle(h: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn GetModuleFileNameA(hModule: HINSTANCE, lpFilename: [*]u8, nSize: u32) callconv(.winapi) u32;
extern "kernel32" fn CreateThread(sa: ?*anyopaque, stackSize: usize, startAddr: *const fn (?*anyopaque) callconv(.winapi) u32, param: ?*anyopaque, flags: u32, id: ?*u32) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalAlloc(uFlags: u32, dwBytes: usize) callconv(.winapi) HANDLE;
extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(.winapi) ?[*]u8;
extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(.winapi) BOOL;

const MSG = extern struct {
    hwnd: HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt_x: i32,
    pt_y: i32,
};

// ── Win32 constants ────────────────────────────────────────────────
const WS_OVERLAPPED: u32 = 0x00000000;
const WS_CAPTION: u32 = 0x00C00000;
const WS_SYSMENU: u32 = 0x00080000;
const WS_CHILD: u32 = 0x40000000;
const WS_VISIBLE: u32 = 0x10000000;
const WS_TABSTOP: u32 = 0x00010000;
const WS_GROUP: u32 = 0x00020000;
const WS_BORDER: u32 = 0x00800000;
const WS_EX_DLGMODALFRAME: u32 = 0x00000001;
const WS_EX_CLIENTEDGE: u32 = 0x00000200;
const ES_AUTOHSCROLL: u32 = 0x0080;
const BS_DEFPUSHBUTTON: u32 = 0x0001;
const BS_AUTOCHECKBOX: u32 = 0x0003;
const BM_SETCHECK: u32 = 0x00F1;
const BM_GETCHECK: u32 = 0x00F0;
const BST_CHECKED: u32 = 1;
const WM_CREATE: u32 = 0x0001;
const WM_DESTROY: u32 = 0x0002;
const WM_CLOSE: u32 = 0x0010;
const WM_COMMAND: u32 = 0x0111;
const WM_SETFONT: u32 = 0x0030;
const WM_SETTEXT: u32 = 0x000C;
const SM_CXSCREEN: c_int = 0;
const SM_CYSCREEN: c_int = 1;
const SWP_NOZORDER: u32 = 0x0004;
const SWP_NOSIZE: u32 = 0x0001;
const SWP_NOACTIVATE: u32 = 0x0010;
const WM_DPICHANGED: u32 = 0x02E0;
const WM_DPICHANGED_AFTERPARENT: u32 = 0x02E3;
const USER_DEFAULT_SCREEN_DPI: u32 = 96;
const GENERIC_READ: u32 = 0x80000000;
const GENERIC_WRITE: u32 = 0x40000000;
const FILE_SHARE_READ: u32 = 1;
const OPEN_EXISTING: u32 = 3;
const CREATE_ALWAYS: u32 = 2;
const FILE_ATTRIBUTE_NORMAL: u32 = 0x80;
const INVALID_HANDLE: HANDLE = @ptrFromInt(@as(usize, @truncate(@as(u128, 0xFFFFFFFFFFFFFFFF))));
const ES_READONLY: u32 = 0x0800;
const IDC_IP: c_int = 101;
const IDC_PORT: c_int = 102;
const IDC_URL: c_int = 103;
const IDC_AUTOSTART: c_int = 104;
const IDC_TOKEN: c_int = 105;
const IDC_GENERATE: c_int = 106;
const IDC_COPY_TOKEN: c_int = 107;
const IDC_AUTHENABLE: c_int = 108;
const IDC_SAVE: c_int = 1;
const IDC_CANCEL: c_int = 2;
const BN_CLICKED: u32 = 0;
const WM_CTLCOLORSTATIC: u32 = 0x0138;
const CF_TEXT: u32 = 1;
const GMEM_MOVEABLE: u32 = 0x0002;
const WHITE_BRUSH: c_int = 0;

extern "advapi32" fn SystemFunction036(buf: [*]u8, len: u32) callconv(.winapi) u8;

// ── DPI awareness ──────────────────────────────────────────────────
// Per-Monitor V2 context value. Must match the Windows SDK definition.
const DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2: ?*anyopaque = @ptrFromInt(@as(usize, @bitCast(@as(isize, -4))));

extern "user32" fn SetThreadDpiAwarenessContext(value: ?*anyopaque) callconv(.winapi) ?*anyopaque;
extern "user32" fn GetDpiForSystem() callconv(.winapi) u32;
extern "user32" fn GetDpiForWindow(hwnd: HWND) callconv(.winapi) u32;
extern "user32" fn GetDlgItem(hDlg: HWND, nIDDlgItem: c_int) callconv(.winapi) HWND;

fn setPerMonitorV2() bool {
    return SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2) != null;
}

/// Scale a 96-DPI design unit by the current DPI.
fn sd(design: c_int, dpi: u32) c_int {
    return @intCast(@divTrunc(@as(i64, design) * dpi, USER_DEFAULT_SCREEN_DPI));
}

fn generateToken(buf: *[32]u8) void {
    var raw: [16]u8 = undefined;
    _ = SystemFunction036(&raw, 16);
    const hex = "0123456789abcdef";
    for (raw, 0..) |b, i| {
        buf[i * 2] = hex[b >> 4];
        buf[i * 2 + 1] = hex[b & 0x0f];
    }
}

// ── Config data ────────────────────────────────────────────────────
pub const Config = struct {
    ip: [64]u8 = undefined,
    ip_len: usize = 0,
    port: u16 = 0,
    auto_start: bool = true,
    auth_enabled: bool = true,
    auth_token: [64]u8 = undefined,
    auth_token_len: usize = 0,

    pub fn ipSlice(self: *const Config) []const u8 {
        return self.ip[0..self.ip_len];
    }

    pub fn tokenSlice(self: *const Config) []const u8 {
        return self.auth_token[0..self.auth_token_len];
    }

    pub fn hasAuth(self: *const Config) bool {
        return self.auth_enabled and self.auth_token_len > 0;
    }
};

var config_path: [512]u8 = undefined;
var config_path_len: usize = 0;

fn getConfigPath() [*:0]const u8 {
    if (config_path_len > 0) return @ptrCast(&config_path);

    var module_path: [512]u8 = undefined;
    const len = GetModuleFileNameA(null, &module_path, 512);
    if (len == 0) {
        const fallback = "mcp_config.json";
        @memcpy(config_path[0..fallback.len], fallback);
        config_path[fallback.len] = 0;
        config_path_len = fallback.len;
        return @ptrCast(&config_path);
    }

    // Find last backslash
    var last_sep: usize = 0;
    for (0..len) |i| {
        if (module_path[i] == '\\') last_sep = i;
    }

    const filename = "mcp_config.json";
    @memcpy(config_path[0 .. last_sep + 1], module_path[0 .. last_sep + 1]);
    @memcpy(config_path[last_sep + 1 .. last_sep + 1 + filename.len], filename);
    config_path[last_sep + 1 + filename.len] = 0;
    config_path_len = last_sep + 1 + filename.len;
    return @ptrCast(&config_path);
}

pub fn load() Config {
    const default_port: u16 = if (@sizeOf(usize) == 8) 9094 else 9095;
    var cfg = Config{ .port = default_port };
    const default_ip = "127.0.0.1";
    @memcpy(cfg.ip[0..default_ip.len], default_ip);
    cfg.ip_len = default_ip.len;

    const path = getConfigPath();
    const h = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, null, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, null);
    if (h == INVALID_HANDLE or h == null) return ensureToken(&cfg);
    defer _ = CloseHandle(h);

    var buf: [512]u8 = undefined;
    var bytes_read: u32 = 0;
    if (ReadFile(h, &buf, 512, &bytes_read, null) == 0) return ensureToken(&cfg);

    const json_data = buf[0..bytes_read];

    // Parse "IpAddress":"<value>"
    if (findJsonString(json_data, "IpAddress")) |ip_val| {
        if (ip_val.len > 0 and ip_val.len < 64) {
            @memcpy(cfg.ip[0..ip_val.len], ip_val);
            cfg.ip_len = ip_val.len;
        }
    }

    // Parse "Port":<number>
    if (findJsonNumber(json_data, "Port")) |port_val| {
        cfg.port = port_val;
    }

    // Parse "AutoStart":true/false
    if (findJsonBool(json_data, "AutoStart")) |val| {
        cfg.auto_start = val;
    }

    // Parse "AuthEnabled":true/false. Legacy configs have no such field:
    // keep the old behavior (auth on, token auto-generated).
    var auth_enabled_found = false;
    if (findJsonBool(json_data, "AuthEnabled")) |val| {
        cfg.auth_enabled = val;
        auth_enabled_found = true;
    }

    // Parse "AuthToken":"<value>"
    if (findJsonString(json_data, "AuthToken")) |token_val| {
        if (token_val.len > 0 and token_val.len <= 64) {
            @memcpy(cfg.auth_token[0..token_val.len], token_val);
            cfg.auth_token_len = token_val.len;
        }
    }
    // New config file (no AuthEnabled field) with no token: keep legacy default = enabled.
    if (!auth_enabled_found and cfg.auth_token_len == 0) cfg.auth_enabled = true;

    return ensureToken(&cfg);
}

fn ensureToken(cfg: *Config) Config {
    if (cfg.auth_enabled and cfg.auth_token_len == 0) {
        var tok: [32]u8 = undefined;
        generateToken(&tok);
        @memcpy(cfg.auth_token[0..32], tok[0..32]);
        cfg.auth_token_len = 32;
        save(cfg);
    }
    return cfg.*;
}

fn findJsonString(data: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":"value"
    var i: usize = 0;
    while (i + key.len + 4 < data.len) : (i += 1) {
        if (data[i] == '"' and i + 1 + key.len < data.len and
            std.mem.eql(u8, data[i + 1 .. i + 1 + key.len], key) and
            data[i + 1 + key.len] == '"')
        {
            var j = i + 2 + key.len;
            while (j < data.len and (data[j] == ':' or data[j] == ' ')) j += 1;
            if (j < data.len and data[j] == '"') {
                j += 1;
                const val_start = j;
                while (j < data.len and data[j] != '"') j += 1;
                return data[val_start..j];
            }
        }
    }
    return null;
}

fn findJsonNumber(data: []const u8, key: []const u8) ?u16 {
    // Search for "key":<number>
    var i: usize = 0;
    while (i + key.len + 3 < data.len) : (i += 1) {
        if (data[i] == '"' and i + 1 + key.len < data.len and
            std.mem.eql(u8, data[i + 1 .. i + 1 + key.len], key) and
            data[i + 1 + key.len] == '"')
        {
            var j = i + 2 + key.len;
            while (j < data.len and (data[j] == ':' or data[j] == ' ')) j += 1;
            const num_start = j;
            while (j < data.len and data[j] >= '0' and data[j] <= '9') j += 1;
            if (j > num_start) {
                return parsePort(data[num_start..j]);
            }
        }
    }
    return null;
}

fn findJsonBool(data: []const u8, key: []const u8) ?bool {
    var i: usize = 0;
    while (i + key.len + 3 < data.len) : (i += 1) {
        if (data[i] == '"' and i + 1 + key.len < data.len and
            std.mem.eql(u8, data[i + 1 .. i + 1 + key.len], key) and
            data[i + 1 + key.len] == '"')
        {
            var j = i + 2 + key.len;
            while (j < data.len and (data[j] == ':' or data[j] == ' ')) j += 1;
            if (j + 4 <= data.len and std.mem.eql(u8, data[j .. j + 4], "true")) return true;
            if (j + 5 <= data.len and std.mem.eql(u8, data[j .. j + 5], "false")) return false;
        }
    }
    return null;
}

fn parsePort(s: []const u8) ?u16 {
    var val: u32 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        val = val * 10 + (c - '0');
        if (val > 65535) return null;
    }
    if (val == 0) return null;
    return @intCast(val);
}

pub fn save(cfg: *const Config) void {
    const path = getConfigPath();
    const h = CreateFileA(path, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (h == INVALID_HANDLE or h == null) return;
    defer _ = CloseHandle(h);

    var buf: [384]u8 = undefined;
    const prefix = "{\"IpAddress\":\"";
    @memcpy(buf[0..prefix.len], prefix);
    var pos: usize = prefix.len;
    @memcpy(buf[pos .. pos + cfg.ip_len], cfg.ip[0..cfg.ip_len]);
    pos += cfg.ip_len;
    const mid = "\",\"Port\":";
    @memcpy(buf[pos .. pos + mid.len], mid);
    pos += mid.len;
    var port_buf: [6]u8 = undefined;
    const port_len = fmtU16(cfg.port, &port_buf);
    @memcpy(buf[pos .. pos + port_len], port_buf[0..port_len]);
    pos += port_len;
    const auto_str = if (cfg.auto_start) ",\"AutoStart\":true" else ",\"AutoStart\":false";
    @memcpy(buf[pos .. pos + auto_str.len], auto_str);
    pos += auto_str.len;

    const auth_str = if (cfg.auth_enabled) ",\"AuthEnabled\":true" else ",\"AuthEnabled\":false";
    @memcpy(buf[pos .. pos + auth_str.len], auth_str);
    pos += auth_str.len;

    if (cfg.auth_token_len > 0) {
        const tok_prefix = ",\"AuthToken\":\"";
        @memcpy(buf[pos .. pos + tok_prefix.len], tok_prefix);
        pos += tok_prefix.len;
        @memcpy(buf[pos .. pos + cfg.auth_token_len], cfg.auth_token[0..cfg.auth_token_len]);
        pos += cfg.auth_token_len;
        buf[pos] = '"';
        pos += 1;
    }

    buf[pos] = '}';
    pos += 1;

    var written: u32 = 0;
    _ = WriteFile(h, &buf, @intCast(pos), &written, null);
}

fn fmtU16(val: u16, buf: *[6]u8) usize {
    if (val == 0) {
        buf[0] = '0';
        return 1;
    }
    var v = val;
    var i: usize = 0;
    while (v > 0) : (i += 1) {
        buf[5 - i] = '0' + @as(u8, @intCast(v % 10));
        v /= 10;
    }
    // Shift to start
    var j: usize = 0;
    while (j < i) : (j += 1) {
        buf[j] = buf[6 - i + j];
    }
    return i;
}

// ── Dialog ─────────────────────────────────────────────────────────

var dlg_hwnd: HWND = null;
var edit_ip: HWND = null;
var edit_port: HWND = null;
var edit_token: HWND = null;
var lbl_url: HWND = null;
var chk_autostart: HWND = null;
var chk_auth: HWND = null;
var btn_generate: HWND = null;
var btn_copy: HWND = null;
var ui_font: HFONT = null;
var ui_font_bold: HFONT = null;
var ui_font_small: HFONT = null;
var class_registered: bool = false;
var parent_hwnd: HWND = null;

const DLG_W = 450;
const DLG_H = 410;
const CLASS_NAME = "MCPServerConfig\x00";

var cur_dpi: u32 = 96;

pub fn showDialog(parentHwnd: usize) void {
    parent_hwnd = @ptrFromInt(parentHwnd);
    _ = CreateThread(null, 0, dialogThread, null, 0, null);
}

fn dialogThread(_: ?*anyopaque) callconv(.winapi) u32 {
    // Opt this thread (and the dialog it creates) into per-monitor DPI scaling
    // without changing the awareness of the host x64dbg process.
    if (!setPerMonitorV2()) {
        // Pre-Win10 Creators Update: fall back to system DPI.
    }

    const hInst = GetModuleHandleA(null);

    if (!class_registered) {
        const wc = WNDCLASSEXA{
            .lpfnWndProc = wndProc,
            .hInstance = hInst,
            .hbrBackground = @ptrFromInt(@as(usize, @intCast(1 + @as(c_int, 15)))),
            .lpszClassName = CLASS_NAME,
            .hCursor = null,
        };
        _ = RegisterClassExA(&wc);
        class_registered = true;
    }

    cur_dpi = GetDpiForSystem();
    createFonts();

    dlg_hwnd = CreateWindowExA(
        WS_EX_DLGMODALFRAME,
        CLASS_NAME,
        "MCP Server Configuration\x00",
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        100,
        100,
        sd(DLG_W, cur_dpi),
        sd(DLG_H, cur_dpi),
        parent_hwnd,
        null,
        hInst,
        null,
    );

    if (dlg_hwnd == null) return 1;

    // Disable parent
    if (parent_hwnd != null) _ = EnableWindow(parent_hwnd, 0);

    // Center on screen
    const sw = GetSystemMetrics(SM_CXSCREEN);
    const sh = GetSystemMetrics(SM_CYSCREEN);
    _ = SetWindowPos(dlg_hwnd, null, @divTrunc(sw - sd(DLG_W, cur_dpi), 2), @divTrunc(sh - sd(DLG_H, cur_dpi), 2), 0, 0, SWP_NOZORDER | SWP_NOSIZE);

    _ = ShowWindow(dlg_hwnd, 5);
    _ = UpdateWindow(dlg_hwnd);

    var msg: MSG = undefined;
    while (GetMessageA(&msg, null, 0, 0) > 0) {
        if (IsDialogMessageA(dlg_hwnd, &msg) == 0) {
            _ = TranslateMessage(&msg);
            _ = DispatchMessageA(&msg);
        }
    }

    if (ui_font != null) { _ = DeleteObject(ui_font); ui_font = null; }
    if (ui_font_bold != null) { _ = DeleteObject(ui_font_bold); ui_font_bold = null; }
    if (ui_font_small != null) { _ = DeleteObject(ui_font_small); ui_font_small = null; }

    return 0;
}

fn createFonts() void {
    if (ui_font != null) _ = DeleteObject(ui_font);
    if (ui_font_bold != null) _ = DeleteObject(ui_font_bold);
    if (ui_font_small != null) _ = DeleteObject(ui_font_small);
    ui_font = CreateFontA(-sd(14, cur_dpi), 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 5, 0, "Segoe UI\x00");
    ui_font_bold = CreateFontA(-sd(14, cur_dpi), 0, 0, 0, 700, 0, 0, 0, 0, 0, 0, 5, 0, "Segoe UI\x00");
    ui_font_small = CreateFontA(-sd(12, cur_dpi), 0, 0, 0, 400, 0, 0, 0, 0, 0, 0, 5, 0, "Segoe UI\x00");
}

fn createCtrl(class: [*:0]const u8, text: ?[*:0]const u8, style: u32, x: c_int, y: c_int, w: c_int, h: c_int, id: c_int) HWND {
    const hInst = GetModuleHandleA(null);
    const hwnd = CreateWindowExA(
        if (std.mem.eql(u8, std.mem.span(class), "EDIT")) WS_EX_CLIENTEDGE else 0,
        class,
        text,
        WS_CHILD | WS_VISIBLE | style,
        sd(x, cur_dpi),
        sd(y, cur_dpi),
        sd(w, cur_dpi),
        sd(h, cur_dpi),
        dlg_hwnd,
        @ptrFromInt(@as(usize, @intCast(id))),
        hInst,
        null,
    );
    if (hwnd != null and ui_font != null) {
        _ = SendMessageA(hwnd, WM_SETFONT, @intFromPtr(ui_font.?), 1);
    }
    return hwnd;
}

fn wndProc(hwnd: HWND, msg: u32, wParam: WPARAM, lParam: LPARAM) callconv(.winapi) LRESULT {
    switch (msg) {
        WM_CREATE => {
            dlg_hwnd = hwnd;
            const cfg = load();

            // Use the actual monitor DPI for the window we just created.
            cur_dpi = GetDpiForWindow(hwnd);
            if (cur_dpi == 0) cur_dpi = GetDpiForSystem();
            createFonts();

            // Row 1: IP Address
            _ = createCtrl("STATIC\x00", "IP Address:\x00", 0, 20, 24, 85, 20, 0);
            edit_ip = createCtrl("EDIT\x00", null, WS_TABSTOP | ES_AUTOHSCROLL, 112, 20, 190, 24, IDC_IP);
            const ip_hint = createCtrl("STATIC\x00", "(0.0.0.0, 127.0.0.1, etc.)\x00", 0, 310, 24, 120, 20, 0);
            if (ip_hint != null and ui_font_small != null)
                _ = SendMessageA(ip_hint, WM_SETFONT, @intFromPtr(ui_font_small.?), 1);

            // Row 2: Port
            _ = createCtrl("STATIC\x00", "Port:\x00", 0, 20, 60, 85, 20, 0);
            edit_port = createCtrl("EDIT\x00", null, WS_TABSTOP | ES_AUTOHSCROLL, 112, 56, 100, 24, IDC_PORT);
            const port_hint = createCtrl("STATIC\x00", "(1 - 65535)\x00", 0, 220, 60, 80, 20, 0);
            if (port_hint != null and ui_font_small != null)
                _ = SendMessageA(port_hint, WM_SETFONT, @intFromPtr(ui_font_small.?), 1);

            // Row 3: Auto Start checkbox
            chk_autostart = createCtrl("BUTTON\x00", "Auto start server on plugin load\x00", WS_TABSTOP | BS_AUTOCHECKBOX, 20, 96, 250, 20, IDC_AUTOSTART);
            if (chk_autostart != null and cfg.auto_start)
                _ = SendMessageA(chk_autostart, BM_SETCHECK, BST_CHECKED, 0);

            // Row 4: Require auth checkbox
            chk_auth = createCtrl("BUTTON\x00", "Require Bearer token authentication\x00", WS_TABSTOP | BS_AUTOCHECKBOX, 20, 132, 280, 20, IDC_AUTHENABLE);
            if (chk_auth != null and cfg.auth_enabled)
                _ = SendMessageA(chk_auth, BM_SETCHECK, BST_CHECKED, 0);

            // Row 5: Auth Token
            _ = createCtrl("STATIC\x00", "Auth Token:\x00", 0, 20, 168, 85, 20, 0);
            edit_token = createCtrl("EDIT\x00", null, WS_TABSTOP | ES_AUTOHSCROLL | ES_READONLY, 112, 164, 190, 24, IDC_TOKEN);
            btn_generate = createCtrl("BUTTON\x00", "Generate\x00", WS_TABSTOP, 310, 164, 65, 24, IDC_GENERATE);
            btn_copy = createCtrl("BUTTON\x00", "Copy\x00", WS_TABSTOP, 380, 164, 45, 24, IDC_COPY_TOKEN);

            const auth_hint = createCtrl("STATIC\x00", "Token is auto-generated on first run and persists across restarts.\x00", 0, 112, 191, 320, 16, 0);
            if (auth_hint != null and ui_font_small != null)
                _ = SendMessageA(auth_hint, WM_SETFONT, @intFromPtr(ui_font_small.?), 1);

            // Row 6: URL preview
            _ = createCtrl("STATIC\x00", "Server URL:\x00", 0, 20, 221, 85, 20, 0);
            lbl_url = createCtrl("STATIC\x00", null, 0, 112, 221, 310, 20, IDC_URL);
            if (lbl_url != null and ui_font_bold != null)
                _ = SendMessageA(lbl_url, WM_SETFONT, @intFromPtr(ui_font_bold.?), 1);

            // Help notes
            const notes = createCtrl("STATIC\x00",
                "Use 0.0.0.0 to listen on all interfaces (for WSL/remote access).\r\nUse 127.0.0.1 for local-only access.\r\nSave will automatically restart the MCP server.\x00",
                0, 20, 246, 400, 52, 0);
            if (notes != null and ui_font_small != null)
                _ = SendMessageA(notes, WM_SETFONT, @intFromPtr(ui_font_small.?), 1);

            // Buttons
            _ = createCtrl("BUTTON\x00", "Save\x00", WS_TABSTOP | BS_DEFPUSHBUTTON, 240, 316, 90, 30, IDC_SAVE);
            _ = createCtrl("BUTTON\x00", "Cancel\x00", WS_TABSTOP, 340, 316, 90, 30, IDC_CANCEL);
            // Set initial values
            if (edit_ip != null) {
                var ip_z: [65]u8 = undefined;
                @memcpy(ip_z[0..cfg.ip_len], cfg.ip[0..cfg.ip_len]);
                ip_z[cfg.ip_len] = 0;
                _ = SendMessageA(edit_ip, WM_SETTEXT, 0, @bitCast(@intFromPtr(&ip_z)));
            }
            if (edit_port != null) {
                var port_buf: [6]u8 = undefined;
                const port_len = fmtU16(cfg.port, &port_buf);
                port_buf[port_len] = 0;
                _ = SendMessageA(edit_port, WM_SETTEXT, 0, @bitCast(@intFromPtr(&port_buf)));
            }
            if (edit_token != null and cfg.auth_token_len > 0) {
                var tok_z: [65]u8 = undefined;
                @memcpy(tok_z[0..cfg.auth_token_len], cfg.auth_token[0..cfg.auth_token_len]);
                tok_z[cfg.auth_token_len] = 0;
                _ = SendMessageA(edit_token, WM_SETTEXT, 0, @bitCast(@intFromPtr(&tok_z)));
            }
            updateUrlPreview();
            updateAuthControls();

            if (edit_ip != null) _ = SetFocus(edit_ip);
            return 0;
        },
        WM_COMMAND => {
            const id: c_int = @intCast(wParam & 0xFFFF);
            const notify: u32 = @intCast((wParam >> 16) & 0xFFFF);

            if (id == IDC_SAVE and notify == BN_CLICKED) {
                onSave(hwnd);
                return 0;
            }
            if (id == IDC_CANCEL and notify == BN_CLICKED) {
                restoreParent();
                _ = DestroyWindow(hwnd);
                return 0;
            }
            if (id == IDC_GENERATE and notify == BN_CLICKED) {
                if (edit_token != null) {
                    var tok: [32]u8 = undefined;
                    generateToken(&tok);
                    var tok_z: [33]u8 = undefined;
                    @memcpy(tok_z[0..32], tok[0..32]);
                    tok_z[32] = 0;
                    _ = SendMessageA(edit_token, WM_SETTEXT, 0, @bitCast(@intFromPtr(&tok_z)));
                }
                return 0;
            }
            if (id == IDC_COPY_TOKEN and notify == BN_CLICKED) {
                if (edit_token != null) {
                    var tbuf: [64]u8 = undefined;
                    const tlen: usize = @intCast(GetWindowTextA(edit_token, &tbuf, 64));
                    if (tlen > 0) {
                        if (OpenClipboard(hwnd) != 0) {
                            _ = EmptyClipboard();
                            const hmem = GlobalAlloc(GMEM_MOVEABLE, tlen + 1);
                            if (hmem != null) {
                                const ptr = GlobalLock(hmem);
                                if (ptr) |p| {
                                    @memcpy(p[0..tlen], tbuf[0..tlen]);
                                    p[tlen] = 0;
                                    _ = GlobalUnlock(hmem);
                                    _ = SetClipboardData(CF_TEXT, hmem);
                                }
                            }
                            _ = CloseClipboard();
                        }
                    }
                }
                return 0;
            }
            if (id == IDC_AUTHENABLE and notify == BN_CLICKED) {
                updateAuthControls();
                return 0;
            }
            // Update URL preview on text change (EN_CHANGE = 0x0300)
            if (notify == 0x0300 and (id == IDC_IP or id == IDC_PORT)) {
                updateUrlPreview();
            }
            return 0;
        },
        WM_CTLCOLORSTATIC => {
            const ctrl: HWND = @ptrFromInt(@as(usize, @bitCast(lParam)));
            if (ctrl == edit_token) {
                const hdc: HDC = @ptrFromInt(wParam);
                _ = SetBkColor(hdc, 0x00FFFFFF);
                return @bitCast(@intFromPtr(GetStockObject(WHITE_BRUSH)));
            }
            return DefWindowProcA(hwnd, msg, wParam, lParam);
        },
        WM_DPICHANGED => {
            // wParam HIWORD = new DPI; lParam = suggested window rect.
            const new_dpi: u32 = @intCast(@as(u32, @truncate(@as(usize, @bitCast(lParam)) >> 16)) & 0xFFFF);
            if (new_dpi == 0 or new_dpi == cur_dpi) return 0;
            cur_dpi = new_dpi;
            const rect: *const RECT = @ptrCast(@alignCast(@as([*]const u8, @ptrFromInt(@as(usize, @bitCast(lParam))))[0..@sizeOf(RECT)].ptr));
            _ = SetWindowPos(
                hwnd,
                null,
                rect.left,
                rect.top,
                rect.right - rect.left,
                rect.bottom - rect.top,
                SWP_NOZORDER | SWP_NOACTIVATE,
            );
            createFonts();
            relayoutChildren();
            return 0;
        },
        WM_CLOSE => {
            restoreParent();
            _ = DestroyWindow(hwnd);
            return 0;
        },
        WM_DESTROY => {
            dlg_hwnd = null;
            PostQuitMessage(0);
            return 0;
        },
        else => return DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

fn restoreParent() void {
    if (parent_hwnd != null) {
        _ = EnableWindow(parent_hwnd, 1);
        _ = SetForegroundWindow(parent_hwnd);
    }
}

/// Reposition every child control (design coordinates, 96-DPI base) after a DPI change.
fn moveCtrl(h: HWND, x: c_int, y: c_int, w: c_int, hgt: c_int) void {
    if (h == null) return;
    _ = SetWindowPos(h, null, sd(x, cur_dpi), sd(y, cur_dpi), sd(w, cur_dpi), sd(hgt, cur_dpi), SWP_NOZORDER | SWP_NOACTIVATE);
}

fn relayoutChildren() void {
    // Row 1: IP Address
    moveCtrl(edit_ip, 112, 20, 190, 24);
    // Row 2: Port
    moveCtrl(edit_port, 112, 56, 100, 24);
    // Row 3-4: checkboxes
    moveCtrl(chk_autostart, 20, 96, 250, 20);
    moveCtrl(chk_auth, 20, 132, 280, 20);
    // Row 5: Auth Token
    moveCtrl(edit_token, 112, 164, 190, 24);
    moveCtrl(btn_generate, 310, 164, 65, 24);
    moveCtrl(btn_copy, 380, 164, 45, 24);
    // Row 6: URL preview
    moveCtrl(lbl_url, 112, 221, 310, 20);
    // Buttons (moved via enum by walking children is overkill; move by known ids)
    if (dlg_hwnd != null) {
        var h: HWND = GetDlgItem(dlg_hwnd, IDC_SAVE);
        moveCtrl(h, 240, 316, 90, 30);
        h = GetDlgItem(dlg_hwnd, IDC_CANCEL);
        moveCtrl(h, 340, 316, 90, 30);
    }
}

fn updateUrlPreview() void {
    if (lbl_url == null or edit_ip == null or edit_port == null) return;

    var ip_buf: [64]u8 = undefined;
    const ip_len: usize = @intCast(GetWindowTextA(edit_ip, &ip_buf, 64));

    var port_buf: [8]u8 = undefined;
    const port_len: usize = @intCast(GetWindowTextA(edit_port, &port_buf, 8));

    var url: [128]u8 = undefined;
    const prefix = "http://";
    @memcpy(url[0..prefix.len], prefix);
    var pos: usize = prefix.len;

    if (ip_len == 0) {
        @memcpy(url[pos .. pos + 7], "0.0.0.0");
        pos += 7;
    } else {
        @memcpy(url[pos .. pos + ip_len], ip_buf[0..ip_len]);
        pos += ip_len;
    }

    url[pos] = ':';
    pos += 1;

    if (port_len == 0) {
        url[pos] = '0';
        pos += 1;
    } else {
        @memcpy(url[pos .. pos + port_len], port_buf[0..port_len]);
        pos += port_len;
    }

    url[pos] = '/';
    pos += 1;
    url[pos] = 0;

    _ = SendMessageA(lbl_url, WM_SETTEXT, 0, @bitCast(@intFromPtr(&url)));
}

fn updateAuthControls() void {
    const enabled: BOOL = if (chk_auth != null and SendMessageA(chk_auth, BM_GETCHECK, 0, 0) == BST_CHECKED) 1 else 0;
    if (edit_token != null) _ = EnableWindow(edit_token, enabled);
    if (btn_generate != null) _ = EnableWindow(btn_generate, enabled);
    if (btn_copy != null) _ = EnableWindow(btn_copy, enabled);
}

fn onSave(hwnd: HWND) void {
    var ip_buf: [64]u8 = undefined;
    const ip_len: usize = @intCast(GetWindowTextA(edit_ip, &ip_buf, 64));

    if (ip_len == 0) {
        _ = MessageBoxA(hwnd, "IP address cannot be empty.\x00", "Validation Error\x00", 0x30);
        return;
    }

    var port_buf: [8]u8 = undefined;
    const port_len: usize = @intCast(GetWindowTextA(edit_port, &port_buf, 8));
    const port = parsePort(port_buf[0..port_len]) orelse {
        _ = MessageBoxA(hwnd, "Port must be a number between 1 and 65535.\x00", "Validation Error\x00", 0x30);
        return;
    };

    const auto_start = if (chk_autostart != null)
        SendMessageA(chk_autostart, BM_GETCHECK, 0, 0) == BST_CHECKED
    else
        true;

    const auth_enabled = if (chk_auth != null)
        SendMessageA(chk_auth, BM_GETCHECK, 0, 0) == BST_CHECKED
    else
        true;

    var tok_buf: [64]u8 = undefined;
    var tok_len: usize = if (edit_token != null)
        @intCast(GetWindowTextA(edit_token, &tok_buf, 64))
    else
        0;

    if (auth_enabled and tok_len == 0) {
        // Never save an enabled-but-empty token (would lock out all clients).
        var tok: [32]u8 = undefined;
        generateToken(&tok);
        @memcpy(tok_buf[0..32], tok[0..32]);
        tok_len = 32;
    }
    if (!auth_enabled) tok_len = 0;

    var cfg = Config{ .port = port, .auto_start = auto_start, .auth_enabled = auth_enabled };
    @memcpy(cfg.ip[0..ip_len], ip_buf[0..ip_len]);
    cfg.ip_len = ip_len;
    if (tok_len > 0) {
        @memcpy(cfg.auth_token[0..tok_len], tok_buf[0..tok_len]);
    }
    cfg.auth_token_len = tok_len;
    save(&cfg);

    mcp.stop();
    mcp.setConfig(cfg.ip[0..cfg.ip_len], cfg.port, cfg.tokenSlice(), cfg.auth_enabled);
    if (cfg.auto_start) mcp.start();

    bridge.logPuts("[x64dbg-MCP Server] Configuration saved.\x00");
    restoreParent();
    _ = DestroyWindow(hwnd);
}
