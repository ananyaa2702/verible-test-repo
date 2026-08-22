"""
KNN Host GUI — Arty A7-100T UART Interface
===========================================

- Auto-detects Arty's FTDI FT2232H UART port (VID 0x0403 / PID 0x6010)
- Connect button disabled until a COM port is visible to the OS
- If firmware already booted before GUI connected, Run button auto-enables
  after 5 s (no need to press reset every time)
- Boot sequence dots removed; boot bytes still logged as text
- Training batch dropdown (dummy): Default + Batch 1..10
- Reveal delay: 600 ms (hardcoded)
- Larger fonts, darker log text
"""

import serial
import serial.tools.list_ports
import threading
import queue
import time
import argparse
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox

# ── Protocol ──────────────────────────────────────────────────────────────────
CMD_RUN          = 0x10
BAUD_RATE        = 115200
REVEAL_DELAY_MS  = 600
ALREADY_RUNNING_TIMEOUT_MS = 5000   # enable Run if nothing heard after this

# ── Arty auto-detection ───────────────────────────────────────────────────────
FPGA_VID = 0x0403   # FTDI
FPGA_PID = 0x6010   # FT2232H on Arty A7

def _autodetect_fpga_port(all_ports):
    candidates = []
    for p in all_ports:
        if p.vid == FPGA_VID and p.pid == FPGA_PID:
            candidates.append((0, p.device))
            continue
        desc = (p.description or "").lower()
        mfr  = (p.manufacturer or "").lower()
        if "digilent" in desc or "digilent" in mfr:
            candidates.append((1, p.device))
        elif "ftdi" in mfr or "ftdi" in desc:
            candidates.append((2, p.device))
    if not candidates:
        return None
    candidates.sort()
    return candidates[0][1]

# ── Ground truth ──────────────────────────────────────────────────────────────
GROUND_TRUTH = [6, 2, 3, 7, 2, 2, 3, 4]

# ── Bootrom byte table ────────────────────────────────────────────────────────
BOOTROM_BYTES = {
    0x0A: ("BRAM test byte 1 = 10 ✓",             "boot"),
    0x14: ("BRAM test byte 2 = 20 ✓",             "boot"),
    0xFE: ("Flash read starting…",                 "boot"),
    0xA1: ("SPI flash read in progress…",          "boot"),
    0xA2: ("Magic word 0xB007B007 verified ✓",     "boot"),
    0xA3: ("Payload read complete ✓",              "boot"),
    0xA4: ("Checksum OK ✓",                        "boot"),
    0xA5: ("Firmware loaded — jumping to main ✓",  "boot"),
    0xFF: ("Firmware idle — waiting for command",   "idle"),
}

# ── Palette ───────────────────────────────────────────────────────────────────
BG        = "#f5f5f7"
PANEL     = "#ffffff"
BORDER    = "#d0d0dc"
ACCENT    = "#6c5ce7"
GREEN     = "#27ae60"
RED       = "#c0392b"
YELLOW    = "#9a6e00"
CYAN      = "#0773c4"
ORANGE    = "#c46a00"
TEXT_FG   = "#1a1a28"
LOG_FG    = "#2a2a3a"
MUTED_FG  = "#52526a"

# ── Fonts ─────────────────────────────────────────────────────────────────────
MONO      = ("Courier New", 12)
LABELFNT  = ("Segoe UI",    11)
TITLEFNT  = ("Segoe UI",    14, "bold")
BTNFNT    = ("Segoe UI",    12, "bold")
SMALLFNT  = ("Segoe UI",    10)
ACCFNT    = ("Segoe UI",    26, "bold")
STATUSFNT = ("Segoe UI",    10)

TAG_COLOURS = {
    "boot":       CYAN,
    "idle":       YELLOW,
    "prediction": GREEN,
    "sent":       ACCENT,
    "error":      RED,
    "warn":       ORANGE,
    "info":       LOG_FG,
}

BATCH_OPTIONS = ["Default dataset"] + [f"Training batch {i}" for i in range(1, 11)]


class KNNGui:
    def __init__(self, root, default_port=None):
        self.root = root
        self.root.title("KNN Host — Arty A7-100T")
        self.root.configure(bg=BG)

        self.serial_port          = None
        self.reader_thread        = None
        self.running              = False

        self.boot_complete        = False
        self.awaiting_predictions = False
        self.predictions          = []
        self.pred_queue           = queue.Queue()
        self.reveal_active        = False
        self.any_byte_received    = False
        self.watchdog_job         = None
        self.already_running_job  = None
        self._forced_port         = default_port

        self._build_ui()
        self._poll_ports()

    # ─── Build UI ─────────────────────────────────────────────────────────────

    def _build_ui(self):
        # Title bar
        top = tk.Frame(self.root, bg=BG, pady=10)
        top.pack(fill="x", padx=16)
        tk.Label(top, text="KNN Host Utility", bg=BG, fg=ACCENT,
                 font=TITLEFNT).pack(side="left")
        self.conn_indicator = tk.Canvas(top, width=18, height=18,
                                        bg=BG, highlightthickness=0)
        self.conn_indicator.pack(side="right", padx=4)
        self._draw_led("#c0c0cc")
        self.status_lbl = tk.Label(top, text="Disconnected",
                                   bg=BG, fg=MUTED_FG, font=LABELFNT)
        self.status_lbl.pack(side="right", padx=8)

        # Connection row
        conn = tk.LabelFrame(self.root, text="Connection", bg=PANEL,
                             fg=TEXT_FG, font=LABELFNT,
                             padx=10, pady=8, bd=1, relief="solid")
        conn.pack(fill="x", padx=16, pady=(0, 6))

        tk.Label(conn, text="Port:", bg=PANEL, fg=TEXT_FG,
                 font=LABELFNT).grid(row=0, column=0, sticky="w")
        self.port_var = tk.StringVar()
        self.port_cb  = ttk.Combobox(conn, textvariable=self.port_var,
                                      width=18, font=LABELFNT)
        self.port_cb.grid(row=0, column=1, padx=(6, 2), sticky="w")
        tk.Button(conn, text="↺", command=self._manual_refresh,
                  bg=PANEL, fg=TEXT_FG, relief="flat",
                  font=("Segoe UI", 12)).grid(row=0, column=2, padx=(0, 10))

        tk.Label(conn, text="Baud:", bg=PANEL, fg=TEXT_FG,
                 font=LABELFNT).grid(row=0, column=3, sticky="w")
        self.baud_var = tk.StringVar(value=str(BAUD_RATE))
        ttk.Combobox(conn, textvariable=self.baud_var, width=9,
                     values=["9600","19200","38400","57600","115200"],
                     font=LABELFNT).grid(row=0, column=4, padx=(6, 14))

        tk.Label(conn, text="Batch:", bg=PANEL, fg=TEXT_FG,
                 font=LABELFNT).grid(row=0, column=5, sticky="w")
        self.batch_var = tk.StringVar(value=BATCH_OPTIONS[0])
        batch_cb = ttk.Combobox(conn, textvariable=self.batch_var,
                                 width=18, state="readonly",
                                 values=BATCH_OPTIONS, font=LABELFNT)
        batch_cb.grid(row=0, column=6, padx=(6, 14))
        batch_cb.bind("<<ComboboxSelected>>", self._on_batch_change)

        self.autodetect_lbl = tk.Label(conn, text="", bg=PANEL,
                                        fg=GREEN, font=SMALLFNT)
        self.autodetect_lbl.grid(row=0, column=7, sticky="w", padx=(0, 8))

        self.conn_btn = tk.Button(conn, text="Connect",
                                  command=self._toggle_conn,
                                  bg=ACCENT, fg="white", relief="flat",
                                  padx=14, pady=4, font=LABELFNT,
                                  state="disabled")
        self.conn_btn.grid(row=0, column=8, sticky="e")
        conn.columnconfigure(7, weight=1)

        # Controls
        ctrl = tk.Frame(self.root, bg=BG, pady=6)
        ctrl.pack(fill="x", padx=16)

        self.run_btn = tk.Button(ctrl, text="▶  Run Default Dataset",
                                 command=self._send_run,
                                 bg=GREEN, fg="white", relief="flat",
                                 padx=18, pady=8, font=BTNFNT,
                                 state="disabled")
        self.run_btn.pack(side="left", padx=(0, 10))

        tk.Button(ctrl, text="Clear Log", command=self._clear,
                  bg=PANEL, fg=TEXT_FG, relief="flat",
                  padx=12, pady=8, font=LABELFNT,
                  highlightbackground=BORDER,
                  highlightthickness=1, bd=1).pack(side="left")

        self.pred_lbl = tk.Label(ctrl, text="Predictions: 0",
                                 bg=BG, fg=YELLOW, font=LABELFNT)
        self.pred_lbl.pack(side="right")

        # Middle: log + accuracy
        mid = tk.Frame(self.root, bg=BG)
        mid.pack(fill="both", expand=True, padx=16, pady=(0, 6))

        log_f = tk.LabelFrame(mid, text="UART Log", bg=PANEL, fg=TEXT_FG,
                              font=LABELFNT, padx=4, pady=4,
                              bd=1, relief="solid")
        log_f.pack(side="left", fill="both", expand=True)

        self.log = scrolledtext.ScrolledText(
            log_f, bg=PANEL, fg=LOG_FG, font=MONO,
            relief="flat", insertbackground=TEXT_FG, wrap="word",
            selectbackground=ACCENT, selectforeground="white")
        self.log.pack(fill="both", expand=True)
        self.log.configure(state="disabled")
        for tag, colour in TAG_COLOURS.items():
            self.log.tag_configure(tag, foreground=colour)

        # Accuracy panel
        acc_f = tk.LabelFrame(mid, text="Accuracy", bg=PANEL, fg=TEXT_FG,
                              font=LABELFNT, padx=12, pady=12,
                              bd=1, relief="solid", width=230)
        acc_f.pack(side="left", fill="y", padx=(10, 0))
        acc_f.pack_propagate(False)

        self.acc_frac_lbl = tk.Label(acc_f, text="—/—", bg=PANEL,
                                      fg=TEXT_FG, font=ACCFNT)
        self.acc_frac_lbl.pack(pady=(4, 0))
        self.acc_pct_lbl  = tk.Label(acc_f, text="No run yet",
                                      bg=PANEL, fg=MUTED_FG, font=LABELFNT)
        self.acc_pct_lbl.pack(pady=(0, 10))
        tk.Frame(acc_f, bg=BORDER, height=1).pack(fill="x", pady=(0, 8))

        self.acc_rows_frame = tk.Frame(acc_f, bg=PANEL)
        self.acc_rows_frame.pack(fill="x")
        self.acc_row_labels = []
        for i in range(8):
            lbl = tk.Label(self.acc_rows_frame, text=f"img{i}   —",
                           bg=PANEL, fg=MUTED_FG, font=MONO, anchor="w")
            lbl.pack(fill="x")
            self.acc_row_labels.append(lbl)

        # Results bar
        sf = tk.LabelFrame(self.root, text="Results", bg=PANEL, fg=TEXT_FG,
                           font=LABELFNT, padx=8, pady=6,
                           bd=1, relief="solid")
        sf.pack(fill="x", padx=16, pady=(0, 8))
        self.summary_var = tk.StringVar(value="(no predictions yet)")
        tk.Label(sf, textvariable=self.summary_var, bg=PANEL, fg=GREEN,
                 font=MONO, anchor="w").pack(fill="x")

        # Status bar
        self.bar = tk.Label(self.root,
                            text="Waiting for a COM port to appear…",
                            bg=PANEL, fg=MUTED_FG, font=STATUSFNT,
                            anchor="w", padx=10, bd=1, relief="solid")
        self.bar.pack(fill="x", side="bottom")

        self._log(
            "KNN Host Utility ready.\n"
            "1. Connect the Arty A7 via USB — port is auto-detected\n"
            "2. Click Connect\n"
            "3. Press the reset button if the board hasn't booted yet\n"
            "   (if it already has, Run enables automatically after 5 s)\n"
            "4. Click Run Default Dataset", "info")

    # ─── Helpers ──────────────────────────────────────────────────────────────

    def _draw_led(self, colour):
        self.conn_indicator.delete("all")
        self.conn_indicator.create_oval(2, 2, 16, 16,
                                         fill=colour, outline="")

    def _set_bar(self, text, colour=None):
        self.bar.configure(text=text, fg=colour or MUTED_FG)

    def _log(self, msg, tag="info"):
        def _w():
            self.log.configure(state="normal")
            ts = time.strftime("%H:%M:%S")
            self.log.insert("end", f"[{ts}] {msg}\n", tag)
            self.log.see("end")
            self.log.configure(state="disabled")
        self.root.after(0, _w)

    def _on_batch_change(self, _event=None):
        sel = self.batch_var.get()
        self._log(
            f"Batch set to '{sel}' — dataset switching is not yet wired "
            "into the firmware; this selection is saved for future use.",
            "warn")

    # ─── Port polling ─────────────────────────────────────────────────────────

    def _poll_ports(self):
        ports   = list(serial.tools.list_ports.comports())
        devices = [p.device for p in ports]
        best    = _autodetect_fpga_port(ports)

        self.port_cb["values"] = devices

        if self._forced_port and self._forced_port in devices:
            self.port_var.set(self._forced_port)
            self._forced_port = None

        if best and not self.port_var.get():
            self.port_var.set(best)

        if best:
            self.autodetect_lbl.configure(
                text=f"✓ Arty on {best}", fg=GREEN)
        elif devices:
            self.autodetect_lbl.configure(
                text="No Arty found — select manually", fg=ORANGE)
        else:
            self.autodetect_lbl.configure(text="No ports found", fg=RED)
            self.port_var.set("")

        if not self.running:
            if devices:
                self.conn_btn.configure(state="normal")
                self._set_bar("Port ready — click Connect.")
            else:
                self.conn_btn.configure(state="disabled")
                self._set_bar("Waiting for a COM port to appear…")

        self.root.after(1000, self._poll_ports)

    def _manual_refresh(self):
        self._poll_ports()

    # ─── Connection ───────────────────────────────────────────────────────────

    def _toggle_conn(self):
        if self.serial_port and self.serial_port.is_open:
            self._disconnect()
        else:
            self._connect()

    def _connect(self):
        port = self.port_var.get().strip()
        baud = int(self.baud_var.get())
        if not port:
            messagebox.showerror("No port", "Select a serial port first.")
            return
        try:
            self.serial_port = serial.Serial(
                port=port, baudrate=baud, timeout=0.2)
        except serial.SerialException as exc:
            self._handle_connect_error(port, exc)
            return

        self.running           = True
        self.any_byte_received = False
        self.boot_complete     = False
        self._draw_led(GREEN)
        self.conn_btn.configure(text="Disconnect", bg=RED)
        self._set_bar(
            f"Connected to {port} @ {baud} baud — "
            "press reset on the Arty if it hasn't booted yet.")
        self._log(
            f"Connected to {port} @ {baud} baud.\n"
            "Press the reset button on the Arty if needed.\n"
            f"If the board already booted, Run enables in "
            f"{ALREADY_RUNNING_TIMEOUT_MS // 1000} s automatically.", "info")

        self.reader_thread = threading.Thread(
            target=self._read_loop, daemon=True)
        self.reader_thread.start()

        # After timeout, assume firmware already running and enable Run
        self.already_running_job = self.root.after(
            ALREADY_RUNNING_TIMEOUT_MS, self._assume_already_running)

    def _assume_already_running(self):
        """Called if no boot bytes arrived — board likely already booted."""
        self.already_running_job = None
        if self.running and not self.boot_complete:
            self.boot_complete = True
            self.root.after(0, lambda: self.run_btn.configure(state="normal"))
            self._log(
                "No boot sequence detected — firmware was already running.\n"
                "Run button enabled. If predictions don't come through,\n"
                "press the reset button on the Arty and wait for boot.",
                "warn")
            self._set_bar(
                "Firmware assumed running — click Run Default Dataset.")

    def _handle_connect_error(self, port, exc):
        msg = str(exc).lower()
        if "cannot find" in msg or "no such file" in msg:
            tip = f"'{port}' doesn't exist. Replug the board and try again."
        elif "access is denied" in msg or "permission" in msg or "busy" in msg:
            tip = (f"'{port}' is open in another program "
                   "(Arduino IDE, Tera Term, PuTTY…). Close it first.")
        else:
            tip = f"Could not open '{port}': {exc}"
        self._log(f"Connection failed: {tip}", "error")
        self._set_bar(tip, RED)
        messagebox.showerror("Connection failed", tip)
        self._draw_led(RED)

    def _disconnect(self):
        self.running = False
        if self.already_running_job:
            self.root.after_cancel(self.already_running_job)
            self.already_running_job = None
        if self.serial_port:
            try:
                self.serial_port.close()
            except Exception:
                pass
        self.serial_port = None
        self._draw_led("#c0c0cc")
        self.conn_btn.configure(text="Connect", bg=ACCENT)
        self.run_btn.configure(state="disabled")
        self._log("Disconnected.", "info")
        self._set_bar("Disconnected.")

    # ─── Reader thread ────────────────────────────────────────────────────────

    def _read_loop(self):
        while self.running:
            try:
                if not self.serial_port or not self.serial_port.is_open:
                    break
                raw = self.serial_port.read(1)
                if not raw:
                    continue
                self.any_byte_received = True
                self._handle_byte(raw[0])
            except serial.SerialException:
                self._log("Serial port disconnected unexpectedly.", "error")
                self.root.after(0, self._disconnect)
                break

    def _handle_byte(self, b: int):
        # Bootrom byte
        if b in BOOTROM_BYTES and not self.awaiting_predictions:
            desc, tag = BOOTROM_BYTES[b]
            self._log(f"← BOOT 0x{b:02X}  {desc}", tag)
            if b == 0xFF:
                # Cancel the "already running" timer — we got real boot bytes
                if self.already_running_job:
                    self.root.after_cancel(self.already_running_job)
                    self.already_running_job = None
                self.boot_complete = True
                self.root.after(0, lambda: self.run_btn.configure(
                    state="normal"))
                self._set_bar("Firmware ready — click Run Default Dataset.")
            return

        # Prediction byte
        if self.awaiting_predictions:
            self.pred_queue.put(b)
            return

        # Unknown
        self._log(
            f"← Unknown byte 0x{b:02X} ({b}) — "
            "noise, wrong baud rate, or board not yet reset", "warn")

    # ─── Throttled reveal ────────────────────────────────────────────────────

    def _reveal_next(self):
        try:
            b = self.pred_queue.get_nowait()
        except queue.Empty:
            self.root.after(50, self._reveal_next)
            return

        if b == 0xFF:
            self.awaiting_predictions = False
            self.reveal_active        = False
            self._log(
                f"← 0xFF  Run complete ({len(self.predictions)} predictions)",
                "idle")
            self.root.after(0, lambda: self.run_btn.configure(state="normal"))
            self._set_bar("Run complete.")
            self._update_accuracy(final=True)
            return

        idx = len(self.predictions) + 1
        self.predictions.append(b)
        self._log(f"← Prediction #{idx}: class {b}  (0x{b:02X})",
                  "prediction")
        self.root.after(0, self._update_predictions_summary)
        self.root.after(0, self._update_accuracy)
        self.root.after(REVEAL_DELAY_MS, self._reveal_next)

    # ─── Accuracy panel ──────────────────────────────────────────────────────

    def _update_accuracy(self, final=False):
        n       = len(self.predictions)
        correct = 0
        for i, p in enumerate(self.predictions):
            truth = GROUND_TRUTH[i] if i < len(GROUND_TRUTH) else None
            row   = self.acc_row_labels[i]
            if truth is None:
                row.configure(text=f"img{i}   {p}  (no truth)",
                              fg=MUTED_FG)
                continue
            ok = (p == truth)
            if ok:
                correct += 1
            row.configure(
                text=f"img{i}   pred={p}  true={truth}  {'✓' if ok else '✗'}",
                fg=GREEN if ok else RED)

        total = min(n, len(GROUND_TRUTH))
        if total == 0:
            self.acc_frac_lbl.configure(text="—/—")
            self.acc_pct_lbl.configure(text="No run yet")
            return

        pct    = 100.0 * correct / total
        colour = GREEN if pct >= 75 else (YELLOW if pct >= 50 else RED)
        self.acc_frac_lbl.configure(text=f"{correct}/{total}", fg=colour)
        self.acc_pct_lbl.configure(
            text=f"{pct:.1f}%  ({'Final' if final else 'Running'})")

    def _reset_accuracy_panel(self):
        self.acc_frac_lbl.configure(text="—/—", fg=TEXT_FG)
        self.acc_pct_lbl.configure(text="No run yet")
        for i, row in enumerate(self.acc_row_labels):
            row.configure(text=f"img{i}   —", fg=MUTED_FG)

    def _update_predictions_summary(self):
        self.pred_lbl.configure(
            text=f"Predictions: {len(self.predictions)}")
        if self.predictions:
            parts = [f"img{i}→{v}" for i, v in enumerate(self.predictions)]
            self.summary_var.set("  ".join(parts))

    # ─── Commands ─────────────────────────────────────────────────────────────

    def _send_run(self):
        if not self.serial_port or not self.serial_port.is_open:
            messagebox.showerror("Not connected", "Connect first.")
            return
        self.predictions          = []
        self.pred_queue           = queue.Queue()
        self.awaiting_predictions = True
        self._reset_accuracy_panel()
        self.root.after(0, self._update_predictions_summary)
        try:
            self.serial_port.write(bytes([CMD_RUN]))
            batch = self.batch_var.get()
            self._log(
                f"→ Sent RUN_DEFAULT_DATASET (0x{CMD_RUN:02X})  [{batch}]",
                "sent")
            self.run_btn.configure(state="disabled")
            self._set_bar("KNN running — waiting for predictions…")
            if not self.reveal_active:
                self.reveal_active = True
                self._reveal_next()
        except serial.SerialException as exc:
            self._log(f"Write error: {exc}", "error")
            self.awaiting_predictions = False

    def _clear(self):
        self.log.configure(state="normal")
        self.log.delete("1.0", "end")
        self.log.configure(state="disabled")
        self.predictions = []
        self.summary_var.set("(no predictions yet)")
        self._update_predictions_summary()
        self._reset_accuracy_panel()
        self.boot_complete = False


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="KNN GUI — Arty A7-100T")
    parser.add_argument("--port", help="e.g. COM3 or /dev/ttyUSB1")
    args = parser.parse_args()

    root = tk.Tk()
    root.geometry("1060x700")
    app = KNNGui(root, default_port=args.port)
    root.protocol("WM_DELETE_WINDOW",
                  lambda: (app._disconnect(), root.destroy()))
    root.mainloop()


if __name__ == "__main__":
    main()
