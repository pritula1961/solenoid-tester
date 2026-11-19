import sys
import json
import serial
import serial.tools.list_ports
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QPushButton, QLabel, QComboBox, QCheckBox, QFileDialog,
    QFrame, QMessageBox, QInputDialog
)
from PyQt6.QtCore import QTimer, Qt
from PyQt6.QtGui import QFont
import pyqtgraph as pg


class MirrorAxisItem(pg.AxisItem):
    """Кастомная ось X для отображения шкалы 0 -> 100 -> 0%"""
    def tickStrings(self, values, scale, spacing):
        strings = []
        for v in values:
            val = int(round(v))
            if 0 <= val <= 100:
                strings.append(str(val))
            elif 100 < val <= 200:
                strings.append(str(200 - val))
            else:
                strings.append("")
        return strings


class SolenoidTesterApp(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Тестер соленоидов ШИМ — v1.0")
        self.resize(1180, 680)

        self.serial_port = None
        self.test_x = []
        self.test_y = []
        self.ref_x = []
        self.ref_y = []
        self.manual_on = False

        self.init_ui()

        # Таймер чтения COM-порта (опрос каждые 5 мс для плавной отрисовки)
        self.read_timer = QTimer()
        self.read_timer.timeout.connect(self.read_serial_data)
        self.read_timer.start(5)

        self.refresh_ports()

    def init_ui(self):
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        main_layout = QVBoxLayout(central_widget)
        main_layout.setContentsMargins(8, 8, 8, 8)
        main_layout.setSpacing(6)

        # ================= ВЕРХНЯЯ ПАНЕЛЬ ИНСТРУМЕНТОВ =================
        top_bar = QHBoxLayout()

        btn_style = """
            QPushButton {
                background-color: #f0f0f0; border: 1px solid #999;
                border-radius: 4px; padding: 6px 10px; font-weight: bold; font-size: 12px;
            }
            QPushButton:hover { background-color: #e2e2e2; }
            QPushButton:pressed { background-color: #d0d0d0; }
        """

        self.btn_open_test = QPushButton("Открыть\nТест файл")
        self.btn_save_test = QPushButton("Сохранить\nТест файл")
        self.btn_open_ref = QPushButton("Открыть как\nЭталон")
        self.btn_save_ref = QPushButton("Сохранить как\nЭталон")
        self.btn_save_bmp = QPushButton("Сохранить\nкак *.png")

        for btn in [self.btn_open_test, self.btn_save_test, self.btn_open_ref, self.btn_save_ref, self.btn_save_bmp]:
            btn.setStyleSheet(btn_style)
            btn.setFixedHeight(46)
            top_bar.addWidget(btn)

        self.btn_open_test.clicked.connect(lambda: self.load_curve(is_ref=False))
        self.btn_save_test.clicked.connect(lambda: self.save_curve(is_ref=False))
        self.btn_open_ref.clicked.connect(lambda: self.load_curve(is_ref=True))
        self.btn_save_ref.clicked.connect(lambda: self.save_curve(is_ref=True))
        self.btn_save_bmp.clicked.connect(self.export_image)

        # Блок цифрового манометра
        pressure_frame = QFrame()
        pressure_frame.setStyleSheet("border: 1px solid #999; border-radius: 4px; background: #fff;")
        pressure_frame.setFixedHeight(46)
        p_layout = QVBoxLayout(pressure_frame)
        p_layout.setContentsMargins(12, 2, 12, 2)
        p_layout.setSpacing(0)
        lbl_p_title = QLabel("Давление")
        lbl_p_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        lbl_p_title.setStyleSheet("border: none; font-size: 11px; font-weight: bold;")
        self.lbl_pressure_val = QLabel("0.0 bar")
        self.lbl_pressure_val.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.lbl_pressure_val.setStyleSheet("border: none; font-size: 16px; font-weight: bold; color: #0055aa;")
        p_layout.addWidget(lbl_p_title)
        p_layout.addWidget(self.lbl_pressure_val)
        top_bar.addWidget(pressure_frame)

        # Блок COM-порта
        com_frame = QFrame()
        com_frame.setStyleSheet("border: 1px solid #999; border-radius: 4px; background: #f8f8f8;")
        com_frame.setFixedHeight(46)
        c_layout = QHBoxLayout(com_frame)
        c_layout.setContentsMargins(6, 4, 6, 4)
        self.combo_ports = QComboBox()
        self.combo_ports.setMinimumWidth(95)
        self.btn_refresh = QPushButton("↻")
        self.btn_refresh.setFixedWidth(28)
        self.btn_refresh.clicked.connect(self.refresh_ports)
        self.btn_connect = QPushButton("Подключить")
        self.btn_connect.setStyleSheet("background: #2ecc71; color: white; font-weight: bold; padding: 4px 8px; border-radius: 3px;")
        self.btn_connect.clicked.connect(self.toggle_connection)
        c_layout.addWidget(self.combo_ports)
        c_layout.addWidget(self.btn_refresh)
        c_layout.addWidget(self.btn_connect)
        top_bar.addWidget(com_frame)

        self.btn_clear = QPushButton("Очистить\nГрафик")
        self.btn_clear.setStyleSheet(btn_style)
        self.btn_clear.setFixedHeight(46)
        self.btn_clear.clicked.connect(self.clear_graph)
        top_bar.addWidget(self.btn_clear)

        main_layout.addLayout(top_bar)

        # ================= РАБОЧАЯ ОБЛАСТЬ (ГРАФИК + ПРАВАЯ ПАНЕЛЬ) =================
        work_layout = QHBoxLayout()

        # Настройка графика pyqtgraph под светлую миллиметровку
        pg.setConfigOption('background', 'w')
        pg.setConfigOption('foreground', 'k')

        bottom_axis = MirrorAxisItem(orientation='bottom')
        bottom_axis.setLabel("Duty cycle % (ШИМ)", **{'font-size': '11pt', 'font-weight': 'bold'})

        self.plot_widget = pg.PlotWidget(axisItems={'bottom': bottom_axis})
        self.plot_widget.setXRange(0, 200, padding=0.01)
        self.plot_widget.setYRange(0, 10, padding=0.02)
        self.plot_widget.showAxis('right')
        self.plot_widget.getAxis('left').setLabel("bar", **{'font-size': '11pt', 'font-weight': 'bold'})
        self.plot_widget.getAxis('right').setLabel("bar", **{'font-size': '11pt', 'font-weight': 'bold'})

        # Настройка сетки с шагом 10 по X и 1 по Y
        self.plot_widget.getAxis('bottom').setTickSpacing(major=10, minor=2)
        self.plot_widget.getAxis('left').setTickSpacing(major=1, minor=0.2)
        self.plot_widget.getAxis('right').setTickSpacing(major=1, minor=0.2)
        self.plot_widget.showGrid(x=True, y=True, alpha=0.45)

        # Линии графиков (Красная = Эталон, Синяя = Текущий тест)
        self.curve_ref = self.plot_widget.plot(pen=pg.mkPen(color='#e74c3c', width=2.2), name="Эталон")
        self.curve_test = self.plot_widget.plot(pen=pg.mkPen(color='#0000cc', width=2.2), name="Тест")

        work_layout.addWidget(self.plot_widget, stretch=1)

        # ================= ПРАВАЯ ПАНЕЛЬ УПРАВЛЕНИЯ =================
        right_panel = QFrame()
        right_panel.setFixedWidth(165)
        right_panel.setStyleSheet("QFrame { border: 1px solid #999; background: #f4f4f4; border-radius: 4px; } QLabel { border: none; font-weight: bold; font-size: 11px; }")
        r_layout = QVBoxLayout(right_panel)
        r_layout.setContentsMargins(10, 10, 10, 10)
        r_layout.setSpacing(8)

        self.btn_test_pwm = QPushButton("Тест ШИМ")
        self.btn_test_pwm.setFixedHeight(42)
        self.btn_test_pwm.setStyleSheet("background: #e67e22; color: white; font-weight: bold; font-size: 13px; border-radius: 4px;")
        self.btn_test_pwm.clicked.connect(self.start_pwm_test)
        r_layout.addWidget(self.btn_test_pwm)

        self.btn_stop = QPushButton("СТОП")
        self.btn_stop.setFixedHeight(28)
        self.btn_stop.setStyleSheet("background: #c0392b; color: white; font-weight: bold; font-size: 11px; border-radius: 4px;")
        self.btn_stop.clicked.connect(self.stop_test)
        r_layout.addWidget(self.btn_stop)

        self.btn_on_off = QPushButton("Test ON/OFF")
        self.btn_on_off.setFixedHeight(34)
        self.btn_on_off.setStyleSheet(btn_style)
        self.btn_on_off.clicked.connect(self.toggle_manual_on_off)
        r_layout.addWidget(self.btn_on_off)

        r_layout.addWidget(QLabel("Количество\nциклов теста:"))
        self.combo_cycles = QComboBox()
        self.combo_cycles.addItems(["1", "2", "3", "5", "10"])
        r_layout.addWidget(self.combo_cycles)

        self.chk_no = QCheckBox("Нормально\nоткрытый\nклапан")
        self.chk_no.setStyleSheet("font-weight: bold; font-size: 11px;")
        r_layout.addWidget(self.chk_no)

        self.btn_leak = QPushButton("Тест на\nУтечку")
        self.btn_leak.setFixedHeight(38)
        self.btn_leak.setStyleSheet(btn_style)
        self.btn_leak.clicked.connect(self.start_leak_test)
        r_layout.addWidget(self.btn_leak)

        r_layout.addWidget(QLabel("Длительность\nТеста (сек):"))
        self.combo_duration = QComboBox()
        self.combo_duration.addItems(["3", "5", "8", "10", "15", "20"])
        self.combo_duration.setCurrentText("5")
        r_layout.addWidget(self.combo_duration)

        r_layout.addWidget(QLabel("Частота ШИМ:"))
        self.combo_freq = QComboBox()
        self.combo_freq.addItems(["300Hz", "500Hz", "800Hz", "1000Hz", "1500Hz", "2000Hz"])
        self.combo_freq.setCurrentText("1000Hz")
        r_layout.addWidget(self.combo_freq)

        r_layout.addWidget(QLabel("Интервал ШИМ:"))
        self.combo_interval = QComboBox()
        self.combo_interval.addItems(["5ms", "7ms", "10ms", "15ms", "20ms"])
        self.combo_interval.setCurrentText("7ms")
        r_layout.addWidget(self.combo_interval)

        r_layout.addStretch()
        work_layout.addWidget(right_panel)
        main_layout.addLayout(work_layout)

    # ================= ЛОГИКА COM-ПОРТА И КОМАНД =================
    def refresh_ports(self):
        self.combo_ports.clear()
        ports = serial.tools.list_ports.comports()
        for p in ports:
            self.combo_ports.addItem(p.device)

    def toggle_connection(self):
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.close()
            self.btn_connect.setText("Подключить")
            self.btn_connect.setStyleSheet("background: #2ecc71; color: white; font-weight: bold; padding: 4px 8px; border-radius: 3px;")
        else:
            port_name = self.combo_ports.currentText()
            if not port_name:
                QMessageBox.warning(self, "Ошибка", "Не выбран COM-порт!")
                return
            try:
                self.serial_port = serial.Serial(port_name, 115200, timeout=0.01)
                self.btn_connect.setText("Отключить")
                self.btn_connect.setStyleSheet("background: #e74c3c; color: white; font-weight: bold; padding: 4px 8px; border-radius: 3px;")
            except Exception as e:
                QMessageBox.critical(self, "Ошибка порта", f"Не удалось открыть {port_name}:\n{e}")

    def send_cmd(self, cmd):
        if self.serial_port and self.serial_port.is_open:
            self.serial_port.write((cmd + "\n").encode('utf-8'))
        else:
            QMessageBox.warning(self, "Нет связи", "Сначала подключитесь к ESP32-C3 по COM-порту!")

    def start_pwm_test(self):
        self.clear_graph(only_test=True)
        freq = int(self.combo_freq.currentText().replace("Hz", ""))
        dur_ms = int(self.combo_duration.currentText()) * 1000
        interval_ms = int(self.combo_interval.currentText().replace("ms", ""))
        cycles = int(self.combo_cycles.currentText())
        no_flag = 1 if self.chk_no.isChecked() else 0
        cmd = f"START,{freq},{dur_ms},{interval_ms},{cycles},{no_flag}"
        self.send_cmd(cmd)

    def stop_test(self):
        self.manual_on = False
        self.btn_on_off.setStyleSheet("background-color: #f0f0f0; border: 1px solid #999; border-radius: 4px; font-weight: bold; font-size: 12px;")
        self.send_cmd("STOP")

    def toggle_manual_on_off(self):
        self.manual_on = not self.manual_on
        if self.manual_on:
            self.btn_on_off.setStyleSheet("background-color: #2ecc71; color: white; border: 1px solid #27ae60; border-radius: 4px; font-weight: bold; font-size: 12px;")
            self.send_cmd("MANUAL,100")
        else:
            self.btn_on_off.setStyleSheet("background-color: #f0f0f0; border: 1px solid #999; border-radius: 4px; font-weight: bold; font-size: 12px;")
            self.send_cmd("MANUAL,0")

    def start_leak_test(self):
        # Подаёт 100% (или 50%) для проверки герметичности клапана под давлением
        duty, ok = QInputDialog.getInt(self, "Тест на утечку", "Введите скважность удержания (%):", 100, 0, 100, 5)
        if ok:
            self.send_cmd(f"MANUAL,{duty}")

    def read_serial_data(self):
        if not (self.serial_port and self.serial_port.is_open):
            return
        try:
            while self.serial_port.in_waiting > 0:
                line = self.serial_port.readline().decode('utf-8', errors='ignore').strip()
                if not line:
                    continue
                if line.startswith("DATA,"):
                    parts = line.split(",")
                    if len(parts) == 4:
                        duty = float(parts[1])
                        pressure = float(parts[2])
                        direction = int(parts[3])
                        self.lbl_pressure_val.setText(f"{pressure:.1f} bar")
                        # Расчёт координаты X (0..100 при подъёме, 100..200 при спуске)
                        x_pos = duty if direction == 0 else (200.0 - duty)
                        # Если начался новый цикл (x_pos резко вернулся в начало), очищаем синюю кривую
                        if len(self.test_x) > 10 and x_pos < 5.0 and self.test_x[-1] > 190.0:
                            self.test_x.clear()
                            self.test_y.clear()
                        self.test_x.append(x_pos)
                        self.test_y.append(pressure)
                        self.curve_test.setData(self.test_x, self.test_y)
                elif line.startswith("IDLE,"):
                    parts = line.split(",")
                    if len(parts) == 2:
                        pressure = float(parts[1])
                        self.lbl_pressure_val.setText(f"{pressure:.1f} bar")
        except Exception:
            pass

    # ================= РАБОТА С ФАЙЛАМИ И ГРАФИКОМ =================
    def clear_graph(self, only_test=False):
        self.test_x.clear()
        self.test_y.clear()
        self.curve_test.setData([], [])
        if not only_test:
            self.ref_x.clear()
            self.ref_y.clear()
            self.curve_ref.setData([], [])

    def save_curve(self, is_ref=False):
        x_data = self.test_x
        y_data = self.test_y
        if not x_data:
            QMessageBox.information(self, "Пусто", "Сначала снимите график теста!")
            return
        title = "Сохранить как Эталон" if is_ref else "Сохранить Тест файл"
        path, _ = QFileDialog.getSaveFileName(self, title, "", "JSON Files (*.json)")
        if path:
            with open(path, "w", encoding="utf-8") as f:
                json.dump({"x": x_data, "y": y_data}, f)
            if is_ref:
                self.ref_x = list(x_data)
                self.ref_y = list(y_data)
                self.curve_ref.setData(self.ref_x, self.ref_y)

    def load_curve(self, is_ref=False):
        title = "Открыть Эталон" if is_ref else "Открыть Тест файл"
        path, _ = QFileDialog.getOpenFileName(self, title, "", "JSON Files (*.json)")
        if path:
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                if is_ref:
                    self.ref_x = data["x"]
                    self.ref_y = data["y"]
                    self.curve_ref.setData(self.ref_x, self.ref_y)
                else:
                    self.test_x = data["x"]
                    self.test_y = data["y"]
                    self.curve_test.setData(self.test_x, self.test_y)
            except Exception as e:
                QMessageBox.critical(self, "Ошибка файла", f"Не удалось прочитать файл:\n{e}")

    def export_image(self):
        path, _ = QFileDialog.getSaveFileName(self, "Сохранить график как картинку", "graph.png", "PNG Files (*.png)")
        if path:
            pixmap = self.plot_widget.grab()
            pixmap.save(path, "PNG")


if __name__ == "__main__":
    app = QApplication(sys.argv)
    window = SolenoidTesterApp()
    window.show()
    sys.exit(app.exec())
