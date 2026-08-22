
import tkinter as tk
from tkinter import ttk, messagebox, scrolledtext
import threading
import queue
import time

from uart import UARTInterface
from protocol import READY, BOOT_LOADING, BATCH_READY

class KNNHostGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("KNN FPGA Host Utility")
        self.root.geometry("850x650")

        self.uart = None
        self.running = False
        self.rx_queue = queue.Queue()

        self.correct = 0
        self.total = 0

        self.build_gui()

    def build_gui(self):
        top = ttk.Frame(self.root, padding=10)
        top.pack(fill="x")

        ttk.Label(top, text="COM Port").grid(row=0,column=0)
        self.port = ttk.Entry(top,width=10)
        self.port.insert(0,"COM3")
        self.port.grid(row=0,column=1,padx=5)

        ttk.Button(top,text="Connect",command=self.connect).grid(row=0,column=2,padx=5)
        ttk.Button(top,text="Disconnect",command=self.disconnect).grid(row=0,column=3,padx=5)

        self.status=tk.StringVar(value="Disconnected")
        ttk.Label(top,textvariable=self.status).grid(row=0,column=4,padx=20)

        cmd=ttk.LabelFrame(self.root,text="Commands",padding=10)
        cmd.pack(fill="x",padx=10,pady=5)

        ttk.Button(cmd,text="Run Default Dataset",command=self.run_default).grid(row=0,column=0,padx=5,pady=5)

        ttk.Label(cmd,text="Batch").grid(row=0,column=1)
        self.batch=ttk.Entry(cmd,width=5)
        self.batch.insert(0,"1")
        self.batch.grid(row=0,column=2)
        ttk.Button(cmd,text="Run Batch",command=self.run_batch).grid(row=0,column=3,padx=5)

        stat=ttk.LabelFrame(self.root,text="Statistics",padding=10)
        stat.pack(fill="x",padx=10,pady=5)

        self.pred=tk.StringVar(value="-")
        self.acc=tk.StringVar(value="0 / 0 (0.00%)")

        ttk.Label(stat,text="Prediction").grid(row=0,column=0)
        ttk.Label(stat,textvariable=self.pred,font=("Arial",12,"bold")).grid(row=0,column=1,padx=10)

        ttk.Label(stat,text="Accuracy").grid(row=0,column=2,padx=10)
        ttk.Label(stat,textvariable=self.acc,font=("Arial",12,"bold")).grid(row=0,column=3)

        self.progress=ttk.Progressbar(self.root,length=800,mode="determinate")
        self.progress.pack(padx=10,pady=5)

        logf=ttk.LabelFrame(self.root,text="Firmware Log")
        logf.pack(fill="both",expand=True,padx=10,pady=5)

        self.log=scrolledtext.ScrolledText(logf,height=20)
        self.log.pack(fill="both",expand=True)

        self.root.after(100,self.process_queue)

    def write_log(self,msg):
        self.log.insert("end",time.strftime("[%H:%M:%S] ")+msg+"\n")
        self.log.see("end")

    def connect(self):
        try:
            self.uart=UARTInterface(self.port.get())
            self.running=True
            threading.Thread(target=self.rx_loop,daemon=True).start()
            self.status.set("Connected")
            self.write_log("Connected")
        except Exception as e:
            messagebox.showerror("UART",str(e))

    def disconnect(self):
        self.running=False
        if self.uart:
            self.uart.close()
        self.status.set("Disconnected")
        self.write_log("Disconnected")

    def run_default(self):
        if self.uart:
            self.uart.run_default_dataset()
            self.write_log("Default dataset command sent")

    def run_batch(self):
        if not self.uart:
            return
        try:
            b=int(self.batch.get())
            self.uart.run_batch(b)
            self.write_log(f"Batch {b} command sent")
        except Exception as e:
            messagebox.showerror("Error",str(e))

    def rx_loop(self):
        while self.running:
            try:
                b=self.uart.read_byte()
                if b is not None:
                    self.rx_queue.put(b)
            except:
                break

    def process_queue(self):
        while not self.rx_queue.empty():
            b=self.rx_queue.get()
            if b==BOOT_LOADING:
                self.write_log("BootROM Loading Firmware")
            elif b==READY:
                self.write_log("Firmware Ready")
            elif b==BATCH_READY:
                self.write_log("Training Batch Loaded")
            else:
                self.pred.set(str(b))
                self.total+=1
                self.acc.set(f"{self.correct} / {self.total} ({(self.correct/self.total*100 if self.total else 0):.2f}%)")
                self.write_log(f"Prediction = {b}")
        self.root.after(100,self.process_queue)

root=tk.Tk()
app=KNNHostGUI(root)
root.mainloop()
